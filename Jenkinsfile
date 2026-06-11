// Plugins auto-installed by server-init.sh via jenkins-plugin-cli

pipeline {
    agent any

    environment {
        AWS_REGION         = 'ap-south-1'
        ECR_FRONTEND       = 'XXXXXXXXXXXX.dkr.ecr.ap-south-1.amazonaws.com/terrafusion-frontend'
        ECR_BACKEND        = 'XXXXXXXXXXXX.dkr.ecr.ap-south-1.amazonaws.com/terrafusion-backend'
        K8S_NAMESPACE      = 'terrafusion'
        K8S_MANIFESTS      = 'k8s/'
        DEPLOY_DIR         = '/opt/terrafusion'
    }

    stages {
        stage('Init') {
            steps {
                script {
                    env.TIMESTAMP = sh(script: 'date +"%Y-%m-%d_%H-%M-%S"', returnStdout: true).trim()
                }
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build Backend') {
            steps {
                script {
                    docker.build("terrafusion-backend:${TIMESTAMP}", "./backend")
                }
            }
        }

        stage('Build Frontend') {
            steps {
                script {
                    docker.build("terrafusion-frontend:${TIMESTAMP}", "./frontend")
                }
            }
        }

        stage('Push to ECR') {
            steps {
                script {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} | \
                            docker login --username AWS --password-stdin ${ECR_BACKEND%/*}
                        docker tag terrafusion-backend:${TIMESTAMP} ${ECR_BACKEND}:${TIMESTAMP}
                        docker tag terrafusion-backend:latest ${ECR_BACKEND}:latest
                        docker tag terrafusion-frontend:${TIMESTAMP} ${ECR_FRONTEND}:${TIMESTAMP}
                        docker tag terrafusion-frontend:latest ${ECR_FRONTEND}:latest
                        docker push ${ECR_BACKEND}:${TIMESTAMP}
                        docker push ${ECR_BACKEND}:latest
                        docker push ${ECR_FRONTEND}:${TIMESTAMP}
                        docker push ${ECR_FRONTEND}:latest
                    """
                }
            }
        }

        stage('Deploy to k3s') {
            steps {
                script {
                    sh """
                        export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
                        kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml set image deployment/backend -n ${K8S_NAMESPACE} \
                            backend=${ECR_BACKEND}:${TIMESTAMP}
                        kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml set image deployment/frontend -n ${K8S_NAMESPACE} \
                            frontend=${ECR_FRONTEND}:${TIMESTAMP}
                    """
                }
            }
        }

        stage('Smoke Test') {
            steps {
                script {
                    try {
                        sh """
                            kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml rollout status deployment/backend -n ${K8S_NAMESPACE} --timeout=120s
                            kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml rollout status deployment/frontend -n ${K8S_NAMESPACE} --timeout=120s
                            sleep 10
                            BACKEND_POD=\$(kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get pod -n ${K8S_NAMESPACE} -l app=backend -o name | head -1)
                            DB_OK=\$(kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml exec -n ${K8S_NAMESPACE} \$BACKEND_POD -- \
                                curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/api/sensors)
                            if [ "\$DB_OK" != "200" ]; then
                                echo "Smoke test failed: /api/sensors returned \$DB_OK"
                                exit 1
                            fi
                            echo "Smoke test passed: DB + API healthy"
                        """
                    } catch (err) {
                        currentBuild.result = 'FAILURE'
                        error('Smoke test failed — triggering rollback')
                    }
                }
            }
        }
    }

    post {
        failure {
            script {
                sh """
                    kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml rollout undo deployment/backend -n ${K8S_NAMESPACE}
                    kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml rollout undo deployment/frontend -n ${K8S_NAMESPACE}
                    echo "Rollback complete — reverted to previous working version"
                """
            }
        }

        success {
            script {
                sh """
                    docker image prune -f > /dev/null 2>&1 || true
                    echo "Deployment successful: ${TIMESTAMP}"
                """
            }
        }
    }
}
