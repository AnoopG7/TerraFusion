pipeline {
    agent any

    environment {
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

        stage('Import to k3s') {
            steps {
                script {
                    sh """
                        docker tag terrafusion-backend:${TIMESTAMP} terrafusion-backend:latest
                        docker tag terrafusion-frontend:${TIMESTAMP} terrafusion-frontend:latest
                        docker save terrafusion-backend:${TIMESTAMP} terrafusion-frontend:${TIMESTAMP} | \
                            sudo k3s ctr images import - || {
                            echo "Batch import failed — trying individual imports"
                            docker save terrafusion-backend:${TIMESTAMP} | sudo k3s ctr images import -
                            docker save terrafusion-frontend:${TIMESTAMP} | sudo k3s ctr images import -
                        }
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
                            backend=terrafusion-backend:${TIMESTAMP}
                        kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml set image deployment/frontend -n ${K8S_NAMESPACE} \
                            frontend=terrafusion-frontend:${TIMESTAMP}
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
                            kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml exec -n ${K8S_NAMESPACE} \$BACKEND_POD -- \
                                sh -c 'wget -q -O - http://localhost:3001/api/health' | grep -q '"status":"ok"'
                            echo "Smoke test passed: API healthy"
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
