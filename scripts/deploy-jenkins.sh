#!/bin/sh
#
# deploy-staging.sh deploys argo to the staging,
# or develop environment.
#

set -e

DOCKER_REGISTRY=${DOCKER_REGISTRY:-stg-commercial-systems.docker-registry.canonical.com}
STAGE=${STAGE:-staging}

DOCKER=${DOCKER:-docker}
KUBECTL=${KUBERCTL:-kubectl}

# If there is a GIT_VERSION set, use that instead of master
if [ -n "${GIT_VERSION}" ]; then
  git checkout $GIT_VERSION
fi

VERSION=`git rev-parse --verify HEAD`
gitver=`git describe --dirty --always`

$DOCKER build --target argocli \
	--build-arg http_proxy \
	--build-arg https_proxy \
	--build-arg no_proxy \
	--build-arg NO_PROXY \
    --build-arg GOPROXY \
	-t ${DOCKER_REGISTRY}/argo-ubuntu-cli:$VERSION  .
    
$DOCKER push ${DOCKER_REGISTRY}/argo-ubuntu-cli:$VERSION

$DOCKER build --target argoexec \
	--build-arg http_proxy \
	--build-arg https_proxy \
	--build-arg no_proxy \
	--build-arg NO_PROXY \
    --build-arg GOPROXY \
	-t ${DOCKER_REGISTRY}/argo-ubuntu-exec:$VERSION  .
$DOCKER push ${DOCKER_REGISTRY}/argo-ubuntu-exec:$VERSION

$DOCKER build --target workflow-controller \
	--build-arg http_proxy \
	--build-arg https_proxy \
	--build-arg no_proxy \
	--build-arg NO_PROXY \
    --build-arg GOPROXY \
	-t ${DOCKER_REGISTRY}/argo-ubuntu-workflow-controller:$VERSION  .
$DOCKER push ${DOCKER_REGISTRY}/argo-ubuntu-workflow-controller:$VERSION

# Configure the images.
mkdir -p k8s/generated

cat << EOF > k8s/generated/deploy-workflow-controller.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: workflow-controller
spec:
  template:
    spec:
      containers:
      - name: workflow-controller
        args:
        - --configmap
        - workflow-controller-configmap
        - --executor-image
        - ${DOCKER_REGISTRY}/argo-ubuntu-exec:${VERSION}
        - --namespaced
EOF

cat << EOF > k8s/generated/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
- ../${STAGE}
patchesStrategicMerge:
- deploy-workflow-controller.yaml
images:
- name: ${DOCKER_REGISTRY}/argo-ubuntu-cli
  newTag: ${VERSION}
- name: ${DOCKER_REGISTRY}/argo-ubuntu-exec
  newTag: ${VERSION}
- name: ${DOCKER_REGISTRY}/argo-ubuntu-workflow-controller
  newTag: ${VERSION}
EOF

$KUBECTL apply -k k8s/generated

# Wait for rollout to complete
$KUBECTL -n argo-$STAGE rollout status deployment/argo-server --timeout 3m
$KUBECTL -n argo-$STAGE rollout status deployment/workflow-controller --timeout 2m
