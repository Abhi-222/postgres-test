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
        stage('1. Checkout Code') {
            steps {
                // Pulls the latest Terraform and Ansible configurations from Git
                checkout scm
            }
        }

        stage('2. Infrastructure Control') {
            steps {
                withCredentials([string(credentialsId: 'ANSIBLE_SSH_PUBLIC_KEY', variable: 'PUBLIC_KEY_CONTENT')]) {
                    dir('terraform') { 
                        sh 'terraform init'
                        
                        script {
                            if (params.PIPELINE_ACTION == 'Deploy Infrastructure') {
                                // Wrap execution inside an env block to guarantee TF picks up the variable
                                withEnv(["TF_VAR_ssh_public_key=${PUBLIC_KEY_CONTENT}"]) {
                                    sh 'terraform apply -auto-approve'
                                }
                                
                                // Extracts the fresh Bastion public IP from Terraform output data
                                env.BASTION_IP = sh(script: 'terraform output -raw bastion_public_ip', returnStdout: true).trim()
                                echo "Live Cloud Bastion Entrypoint IP: ${env.BASTION_IP}"
                            } else {
                                sh 'terraform destroy -auto-approve'
                            }
                        }
                    }
                }
            }
        }

        stage('3. Configure SSH Tunnel Proxy') {
            when {
                expression { params.PIPELINE_ACTION == 'Deploy Infrastructure' }
            }
            steps {
                // Generates the proxy routing configuration file cleanly without writing key files
                sh """
                    cat << EOF > ${WORKSPACE}/ansible.cfg
[defaults]
host_key_checking = False
deprecation_warnings = False

[ssh_connection]
ssh_args = -o ProxyJump="ubuntu@${env.BASTION_IP}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
EOF
                """
            }
        }

        stage('4. Ansible Configuration Deployment') {
            when {
                expression { params.PIPELINE_ACTION == 'Deploy Infrastructure' }
            }
            steps {
                // --- THE KEY FIX: Loads the key cleanly into memory to bypass libcrypto errors ---
                sshagent(['ANSIBLE_SSH_KEY']) {
                    withEnv([
                        "AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}",
                        "AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}",
                        "AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION}",
                        "ANSIBLE_CONFIG=${WORKSPACE}/ansible.cfg"
                    ]) {
                        sh '''
                            pip install boto3 botocore --break-system-packages || pip install boto3 botocore
                            ansible-galaxy collection install amazon.aws
                            
                            # Runs your playbook utilizing the native secure memory ssh-agent context
                            ansible-playbook -i my_inventory.aws_ec2.yml site.yml -u ubuntu
                        '''
                    }
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
            echo '❌ Pipeline failed. Check the stage console logs for formatting or networking blocks.'
        }
    }
}

