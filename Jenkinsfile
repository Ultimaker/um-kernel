pipeline
{
    agent
    {
        node
        {
            label 'embedded-docker'
        }
    }
    environment
    {
        MAKEFLAGS = '-j 3'
        PACKAGE_NAME = 'um_kernel'
        DOCKER_CONTAINER_NAME = 'um-kernel_build'
        DOCKER_IMAGE_NAME = 'um-kernel_image'
        BUILD_OUTPUT_DIR = '_build_armhf'
    }
    stages
    {
        stage('Prepare')
        {
            steps
            {
                echo "Starting with a clean environment"
                step([$class: 'WsCleanup'])
                checkout scm
                sh 'git submodule update --init --recursive'
            }
        }
        stage('Build docker image')
        {
            steps
            {
                echo "Starting build of ${DOCKER_IMAGE_NAME}_${BUILD_NUMBER}"
                sh 'docker build . -t ${DOCKER_IMAGE_NAME}_${BUILD_NUMBER}'
            }
        }
        stage('Build package')
        {
            steps
            {
                script
                {
                    env.userId = sh (
                        script: 'id -u',
                        returnStdout: true
                    ).trim()
                }

                echo "Starting build of ${PACKAGE_NAME}"
                sh "mkdir -p ${BUILD_OUTPUT_DIR}"
                sh "docker run --name ${DOCKER_CONTAINER_NAME}_${BUILD_NUMBER} --rm -e MAKEFLAGS='-j 3' -v ${WORKSPACE}/${BUILD_OUTPUT_DIR}:/workspace/${BUILD_OUTPUT_DIR} -u ${env.userId} ${DOCKER_IMAGE_NAME}_${BUILD_NUMBER} all"
            }
            post
            {
                success
                {
                    echo "Build of ${PACKAGE_NAME} successful"
                    // We need to find a solution for artifact storage, for now leave it commented
                    // archiveArtifacts artifacts: "${BUILD_OUTPUT_DIR}/*.deb", fingerprint: true

                }
            }
        }
    }
    post
    {
        always
        {
            echo "Cleanup Docker image and Jenkins working directory"
            sh "docker rmi ${DOCKER_IMAGE_NAME}_${BUILD_NUMBER}"
            deleteDir()
        }
        unstable
        {
            echo "Build of ${PACKAGE_NAME} unstable"
        }
        failure
        {
            script
            {
                env.committerEmailAddress = sh (
                    script: 'git --no-pager show -s --format=\'%ae\'',
                    returnStdout: true
                ).trim()
            }

            echo "Build of ${PACKAGE_NAME} failed"
            mail to: "${env.committerEmailAddress}",
                subject: "Failed Pipeline: ${currentBuild.fullDisplayName}",
                body: "Please go to ${env.BUILD_URL}/consoleText for more details.";
        }
    }
}
