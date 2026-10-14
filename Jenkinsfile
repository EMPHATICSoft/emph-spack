// Jenkins job emph-spack-build: build the EMPHATIC release environment and keep
// env/ and bc/ (signed buildcache) as artifacts for bin/publish-emph-environment.sh.
//
// Job setup: Pipeline, "Pipeline script from SCM" pointing at this repo and branch.
// Credential: a "Secret file" with id emph-spack-gpg holding the exported private key.
pipeline {
  agent { label 'alma9' }  // the AL9 build agents' label on buildmaster
  options {
    timeout(time: 8, unit: 'HOURS')
    buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '3'))
    disableConcurrentBuilds()
  }
  parameters {
    string(name: 'ENV_NAME', defaultValue: 'emph-v1.1.1',
           description: 'environments/<ENV_NAME>/spack.yaml to build')
    string(name: 'SPACK_VERSION', defaultValue: 'fnal-v1.1.1')
  }
  stages {
    stage('clean') {
      steps { sh 'rm -rf spack env bc tmp bootstrap timing.txt' }
    }
    stage('build') {
      steps {
        withCredentials([file(credentialsId: 'emph-spack-gpg', variable: 'GPG_KEY')]) {
          sh 'bin/build-emph-environment.sh -w "$WORKSPACE" -k "$GPG_KEY" -e "$ENV_NAME" -s "$SPACK_VERSION"'
        }
      }
    }
  }
  post {
    always {
      archiveArtifacts artifacts: 'env/spack.yaml, env/spack.lock, env/BUILD-INFO, env/concretized.txt, timing.txt',
                       allowEmptyArchive: true
    }
    success {
      archiveArtifacts artifacts: 'bc/**'
    }
  }
}
