pipeline {
  agent any

  environment {
    AWS_REGION = 'us-east-1'
    AWS_CREDENTIALS = 'aws-credentials'
    IMAGE_TAG = "${env.BUILD_ID}"
    CLUSTER_NAME = 'backend-cluster'
    EXECUTION_ROLE_ARN = 'arn:aws:iam::266735801741:role/ECSRoleForJenkins'
    TASK_ROLE_ARN = ''
    CONTAINER_PORT = '8000'  
  }

  stages {
    stage('Setup Environment') {
      steps {
        script {
  
          if (env.BRANCH_NAME == 'main') {
            env.SERVICE_NAME = 'node-backend'
            env.ECR_REPO = 'backend-nodemon'
            env.CONTAINER_PORT = '3000'
            echo "🔧 Deploying Node.js backend..."
          } else if (env.BRANCH_NAME == 'Python') {
            env.SERVICE_NAME = 'uvicorn-backend'
            env.ECR_REPO = 'backend-uvicorn'
            env.CONTAINER_PORT = '8000' // or 8001 if different
            echo "🔧 Deploying Uvicorn backend..."
          } else {
            error "❌ Unknown branch: ${env.BRANCH_NAME}. Allowed: node-backend, uvicorn-backend."
          }

          env.TASK_FAMILY = "${env.SERVICE_NAME}-task"
        }
      }
    }

    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('AWS Login') {
      steps {
        withCredentials([usernamePassword(credentialsId: env.AWS_CREDENTIALS, passwordVariable: 'AWS_SECRET', usernameVariable: 'AWS_KEY')]) {
          sh '''
            export AWS_ACCESS_KEY_ID=$AWS_KEY
            export AWS_SECRET_ACCESS_KEY=$AWS_SECRET
            aws sts get-caller-identity --region $AWS_REGION
          '''
        }
      }
    }

    stage('Create/Get ECR Repo') {
      steps {
        sh '''
          aws ecr describe-repositories --repository-names $ECR_REPO --region $AWS_REGION >/dev/null 2>&1 || \
          aws ecr create-repository --repository-name $ECR_REPO --region $AWS_REGION
        '''
      }
    }

    stage('Build & Push Docker Image') {
      steps {
        withCredentials([usernamePassword(credentialsId: env.AWS_CREDENTIALS, passwordVariable: 'AWS_SECRET', usernameVariable: 'AWS_KEY')]) {
          sh '''
            export AWS_ACCESS_KEY_ID=$AWS_KEY
            export AWS_SECRET_ACCESS_KEY=$AWS_SECRET
            ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region $AWS_REGION)
            ECR_URI="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO}"

            aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

            echo "🚧 Building Docker image for ${SERVICE_NAME}..."
            docker build -t ${ECR_REPO}:${IMAGE_TAG} .
            docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_URI}:${IMAGE_TAG}
            docker push ${ECR_URI}:${IMAGE_TAG}

            docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_URI}:latest
            docker push ${ECR_URI}:latest

            echo "IMAGE_URI=${ECR_URI}:${IMAGE_TAG}" > image_details.txt
          '''
        }
        stash includes: 'image_details.txt', name: 'imagefile'
      }
    }

    stage('Register ECS Task Definition') {
      steps {
        unstash 'imagefile'
        sh '''
          export IMAGE_URI=$(cat image_details.txt | cut -d'=' -f2)
          cat > taskdef.json <<EOF
          {
            "family": "${TASK_FAMILY}",
            "networkMode": "awsvpc",
            "requiresCompatibilities": ["FARGATE"],
            "cpu": "256",
            "memory": "512",
            "executionRoleArn": "${EXECUTION_ROLE_ARN}",
            "taskRoleArn": "${TASK_ROLE_ARN}",
            "containerDefinitions": [
              {
                "name": "${SERVICE_NAME}",
                "image": "${IMAGE_URI}",
                "portMappings": [{ "containerPort": ${CONTAINER_PORT}, "protocol": "tcp" }],
                "essential": true,
                "logConfiguration": {
                  "logDriver": "awslogs",
                  "options": {
                    "awslogs-group": "/ecs/${SERVICE_NAME}",
                    "awslogs-region": "${AWS_REGION}",
                    "awslogs-stream-prefix": "ecs"
                  }
                }
              }
            ]
          }
          EOF

          aws ecs register-task-definition --cli-input-json file://taskdef.json --region $AWS_REGION > taskdef_register.json
        '''
      }
    }

    stage('Create/Update ECS Service') {
      steps {
        sh '''
          SERVICE_STATUS=$(aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --region ${AWS_REGION} --query 'services[0].status' --output text 2>/dev/null || echo "NONE")

          if [ "$SERVICE_STATUS" = "ACTIVE" ]; then
            echo "Updating existing ECS service..."
            TASKDEF_ARN=$(jq -r '.taskDefinition.taskDefinitionArn' taskdef_register.json)
            aws ecs update-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --task-definition ${TASKDEF_ARN} --desired-count 1 --region ${AWS_REGION}
          else
            echo "Creating new ECS service..."
            TASKDEF_ARN=$(jq -r '.taskDefinition.taskDefinitionArn' taskdef_register.json)
            aws ecs create-service \
              --cluster ${CLUSTER_NAME} \
              --service-name ${SERVICE_NAME} \
              --task-definition ${TASKDEF_ARN} \
              --desired-count 1 \
              --launch-type FARGATE \
              --region ${AWS_REGION} \
              --network-configuration "awsvpcConfiguration={assignPublicIp=ENABLED}"
          fi
        '''
      }
    }

    stage('Done') {
      steps {
        echo "✅ Deployment completed for ${env.SERVICE_NAME}"
      }
    }
  }

  post {
    failure {
      echo "❌ Deployment failed for ${env.BRANCH_NAME}"
    }
  }
}
