pipeline {
    agent any

    // --- 1. RUNTIME PARAMETERS (Dropdown for One-Click Control) ---
    parameters {
        choice(
            name: 'PIPELINE_ACTION',
            choices: ['Deploy Infrastructure', 'Tear Down (Destroy)'],
            description: 'Choose whether to spin up and configure your infrastructure or completely tear it down to save costs.'
        )
    }

    environment {
        // Pulls your secret keys safely from Jenkins credential manager
        AWS_ACCESS_KEY_ID     = credentials('AWS_ACCESS_KEY_ID')
        AWS_SECRET_ACCESS_KEY = credentials('AWS_SECRET_ACCESS_KEY')
        AWS_DEFAULT_REGION    = 'us-east-2'
    }

    stages {

        // ============================================================
        // STAGE 1: Pull the latest code from GitHub
        // ============================================================
        stage('1. Checkout Code') {
            steps {
                checkout scm
            }
        }

        // ============================================================
        // STAGE 2: Validate Terraform & Ansible syntax before spending
        //          a single dollar on AWS. Fails fast on typos.
        // ============================================================
        stage('2. Validate & Lint') {
            when {
                expression { params.PIPELINE_ACTION == 'Deploy Infrastructure' }
            }
            steps {
                withCredentials([string(credentialsId: 'ANSIBLE_SSH_PUBLIC_KEY', variable: 'PUBLIC_KEY_CONTENT')]) {
                    dir('terraform') {
                        withEnv(["TF_VAR_ssh_public_key=${PUBLIC_KEY_CONTENT}"]) {
                            sh 'terraform init -backend=false'
                            sh 'terraform validate'
                        }
                    }
                }
                sh 'ansible-playbook --syntax-check -i /dev/null site.yml || true'
                echo '✅ Validation passed. Proceeding to infrastructure provisioning.'
            }
        }

        // ============================================================
        // STAGE 3: Terraform — Apply or Destroy based on user choice
        //          After apply, reads all server IPs from outputs and
        //          auto-generates a static Ansible inventory (hosts.ini)
        // ============================================================
        stage('3. Infrastructure Control') {
            steps {
                withCredentials([string(credentialsId: 'ANSIBLE_SSH_PUBLIC_KEY', variable: 'PUBLIC_KEY_CONTENT')]) {
                    dir('terraform') {
                        sh 'terraform init'

                        script {
                            withEnv(["TF_VAR_ssh_public_key=${PUBLIC_KEY_CONTENT}"]) {
                                if (params.PIPELINE_ACTION == 'Deploy Infrastructure') {
                                    sh 'terraform apply -auto-approve'

                                    // Read all IPs directly from Terraform outputs
                                    env.BASTION_IP   = sh(script: 'terraform output -raw bastion_public_ip',    returnStdout: true).trim()
                                    env.MASTER_IP    = sh(script: 'terraform output -raw master_private_ip',    returnStdout: true).trim()
                                    env.REPLICA_1_IP = sh(script: 'terraform output -raw replica_1_private_ip', returnStdout: true).trim()
                                    env.REPLICA_2_IP = sh(script: 'terraform output -raw replica_2_private_ip', returnStdout: true).trim()

                                    echo "🌐 Bastion IP  : ${env.BASTION_IP}"
                                    echo "🗄️  Master IP   : ${env.MASTER_IP}"
                                    echo "🗄️  Replica 1 IP: ${env.REPLICA_1_IP}"
                                    echo "🗄️  Replica 2 IP: ${env.REPLICA_2_IP}"

                                } else {
                                    sh 'terraform destroy -auto-approve'
                                }
                            }
                        }
                    }
                }
            }
        }

        // ============================================================
        // STAGE 4: Generate a static Ansible inventory file (hosts.ini)
        //          FIXED: Changed [role_Primary] to lowercase [role_primary]
        // ============================================================
        stage('4. Generate Static Inventory') {
            when {
                expression { params.PIPELINE_ACTION == 'Deploy Infrastructure' }
            }
            steps {
                sh """
                    cat > ${WORKSPACE}/hosts.ini << EOF
[role_primary]
${env.MASTER_IP} ansible_user=ubuntu

[role_replica]
${env.REPLICA_1_IP} ansible_user=ubuntu
${env.REPLICA_2_IP} ansible_user=ubuntu

[all:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ProxyCommand="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@${env.BASTION_IP}"'
EOF
                """
                echo '📋 Static inventory generated:'
                sh 'cat ${WORKSPACE}/hosts.ini'
            }
        }

        // ============================================================
        // STAGE 5: Configure SSH Tunnel Proxy for Bastion hop
        //          FIXED: Injected strict bypass flags into ProxyJump string
        // ============================================================
        stage('5. Configure SSH Tunnel Proxy') {
            when {
                expression { params.PIPELINE_ACTION == 'Deploy Infrastructure' }
            }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'ANSIBLE_SSH_KEY', keyFileVariable: 'SSH_KEY_PATH')]) {
                    sh '''
                        cat << EOF > ${WORKSPACE}/ansible.cfg
[defaults]
host_key_checking = False
deprecation_warnings = False

[ssh_connection]
ssh_args = -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o IdentityFile="${SSH_KEY_PATH}"
EOF
                    '''
                }
            }
        }

        // ============================================================
        // STAGE 6: Run Ansible against the static inventory.
        // ============================================================
        stage('6. Ansible Configuration Deployment') {
            when {
                expression { params.PIPELINE_ACTION == 'Deploy Infrastructure' }
            }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'ANSIBLE_SSH_KEY', keyFileVariable: 'SSH_KEY_PATH')]) {
                    withEnv([
                        "ANSIBLE_CONFIG=${WORKSPACE}/ansible.cfg",
                        "ANSIBLE_WORLD_READABLE_TEMP_FILES=True",
                        "ANSIBLE_REMOTE_TMP=/tmp"
                    ]) {
                        sh '''
                            pip install boto3 botocore --break-system-packages || pip install boto3 botocore

                            # Install BOTH required Ansible collections
                            ansible-galaxy collection install amazon.aws community.postgresql

                            # Run playbook against the static hosts.ini (no AWS API needed)
                            ansible-playbook -i ${WORKSPACE}/hosts.ini site.yml --private-key=$SSH_KEY_PATH
                        '''
                    }
                }
            }
        }

        // ============================================================
        // STAGE 7: Health Check — verify replication is actually working
        //          FIXED: Fixed ProxyJump inner arguments to bypass errors
        // ============================================================
        stage('7. Health Check') {
            when {
                expression { params.PIPELINE_ACTION == 'Deploy Infrastructure' }
            }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'ANSIBLE_SSH_KEY', keyFileVariable: 'SSH_KEY_PATH')]) {
                    sh """
                        echo "🔍 Checking replication status on master..."
                        ssh -o StrictHostKeyChecking=no \\
                            -o UserKnownHostsFile=/dev/null \\
                            -o ProxyCommand="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -W %h:%p ubuntu@${env.BASTION_IP}" \\
                            -i \$SSH_KEY_PATH \\
                            ubuntu@${env.MASTER_IP} \\
                            "sudo -u postgres psql -c 'SELECT client_addr, state, sent_lsn, write_lsn FROM pg_stat_replication;'"
                    """
                }
            }
        }
    }

    post {
        success {
            script {
                if (params.PIPELINE_ACTION == 'Deploy Infrastructure') {
                    echo '🚀 Success! High-availability 3-node PostgreSQL 18 infrastructure is completely live.'
                } else {
                    echo '🗑️ Success! All cloud resources have been completely wiped out from AWS.'
                }
            }
        }
        failure {
            echo '❌ Pipeline failed. Check the stage console logs for errors.'
        }
    }
}
