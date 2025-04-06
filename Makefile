# If running in wsl, go to Docker Desktop > Settings > Resources > WSL
# Integration and toggle to enable docker in the distribution of choice. If not,
# have to install docker, which is not covered here.
SCRIPT_DIR=$$(pwd)
SHELL=/bin/bash

# Execute 1 by 1
# Watch this for sudo prompts
# If on wsl or if create_cluster runs into permission issues with docker, make docker_groups and restart shell.
# install_kubeflow_pipelines can take 20 mins.
# Access localhost:8080 after setup and port forwarding
setup: \
	setup_python \
	install_kind \
	install_kubectl \
	create_cluster \
	install_kubeflow_pipelines \
	ml_pipeline_ui_port_forward

setup_python: \
	install_python \
	install_pyenv \
	create_venv \
	install_requirements

# --------------------------------------------------
#  Environment variables and cli
# --------------------------------------------------
define setup_environment
	set -a && \
	source $(SCRIPT_DIR)/envs/base.env && \
	source $(SCRIPT_DIR)/envs/derived.env && \
	set +a
endef

kubectl_set_context:
	@$(setup_environment) && \
	kubectl config use-context $${KUBECTL_CONTEXT} > /dev/null && \
	[ $$(kubectl config current-context) = $${KUBECTL_CONTEXT} ]

kubectl_set_namespace:
	@$(setup_environment) && \
	kubectl config set-context --current --namespace=kubeflow > /dev/null && \
	[ $$(kubectl config view --minify -o jsonpath='{..namespace}') = $${KUBECTL_NAMESPACE} ]

# --------------------------------------------------
#  Kubernetes
# --------------------------------------------------
# https://kind.sigs.k8s.io/docs/user/quick-start/#installation
install_kind:
	@$(setup_environment) && \
	echo "Installing kind" && \
	[ $$(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64 && \
	chmod +x ./kind && \
	sudo mv ./kind /usr/local/bin/kind && \
	rm -rf ./kind && \
	kind --version

# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
install_kubectl:
	@$(setup_environment) && \
	echo "Installing kubectl $${KUBECTL_VERSION}" && \
	[ $$(uname -m) = x86_64 ] && curl -LO "https://dl.k8s.io/release/v$${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
	curl -LO "https://dl.k8s.io/release/v$${KUBECTL_VERSION}/bin/linux/amd64/kubectl.sha256" && \
	echo "$$(cat kubectl.sha256)  kubectl" | sha256sum --check && \
	sudo mv ./kubectl /usr/local/bin/kubectl && \
	kubectl version --client --output=yaml && \
	rm -rf kubectl.sha256

docker_groups:
	@$(setup_environment) && \
	sudo addgroup --system docker && \
	sudo adduser ${USER} docker && \
	sudo chown root:docker /var/run/docker.sock && \
	sudo chmod g+w /var/run/docker.sock

# (getent group docker | grep docker > /dev/null || sudo addgroup --system docker) && \
# (getent group docker | grep ${USER} > /dev/null || sudo adduser ${USER} docker) && \

create_cluster:
	@$(setup_environment) && \
	kind create cluster \
		--name=$${CLUSTER_NAME} \
		--image=$${KIND_IMAGE} \
		--wait 2m

delete_cluster:
	@$(setup_environment) && \
	kind delete clusters $${CLUSTER_NAME}

cluster_info:
	@$(setup_environment) && \
	kubectl cluster-info --context $${KUBECTL_CONTEXT}

list_clusters:
	@$(setup_environment) && \
	kind get clusters

list_pods:
	@$(setup_environment) && \
	kubectl get pods --context $${KUBECTL_CONTEXT} --namespace $${KUBECTL_NAMESPACE}

list_nodes:
	@$(setup_environment) && \
	kubectl get nodes --context $${KUBECTL_CONTEXT} --namespace $${KUBECTL_NAMESPACE}

list_services:
	@$(setup_environment) && \
	kubectl get services --context $${KUBECTL_CONTEXT} --namespace $${KUBECTL_NAMESPACE}

list_namespaces:
	@$(setup_environment) && \
	kubectl get namespace --context $${KUBECTL_CONTEXT}

list_contexts:
	@$(setup_environment) && \
	kubectl config get-contexts

list_deployments:
	@$(setup_environment) && \
	kubectl get deployments --context $${KUBECTL_CONTEXT} --namespace $${KUBECTL_NAMESPACE}

kubectl_view_config:
	@$(setup_environment) && \
	kubectl config view

# --------------------------------------------------
#  Kubeflow Pipelines
# --------------------------------------------------
install_kubeflow_pipelines: kubectl_set_context kubectl_set_namespace
	@$(setup_environment) && \
	kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/cluster-scoped-resources?ref=$${KUBEFLOW_PIPELINES_VERSION}" && \
	kubectl wait --for condition=established --timeout=60s crd/applications.app.k8s.io && \
	kubectl apply -k "github.com/kubeflow/pipelines/manifests/kustomize/env/dev?ref=$${KUBEFLOW_PIPELINES_VERSION}"

ml_pipeline_ui_port_forward: kubectl_set_context kubectl_set_namespace
	@$(setup_environment) && \
	POD_NAME=$$(kubectl get pods --output custom-columns=":metadata.name" --no-headers | grep "ml-pipeline-ui") && \
	kubectl wait --for=condition=ready pod/$${POD_NAME} --timeout=20m && \
	kubectl port-forward -n $${KUBECTL_NAMESPACE} svc/ml-pipeline-ui 8080:80

# --------------------------------------------------
#  Python and virtualenv
# --------------------------------------------------
install_python:
	@sudo apt update && \
	sudo apt-get install -y python3 python3-pip && \
	sudo apt install -y build-essential libssl-dev zlib1g-dev \
		libbz2-dev libreadline-dev libsqlite3-dev curl \
		libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

install_pyenv:
	./scripts/install_pyenv.sh

create_venv:
	@$(setup_environment) && \
	pyenv install $${PYTHON_VERSION} --skip-existing && \
	pyenv uninstall --force $${VENV_NAME} && \
	pyenv virtualenv $${PYTHON_VERSION} $${VENV_NAME} -f && \
	pyenv local $${VENV_NAME}

install_requirements:
	@pip install -r requirements.txt

lock_dependencies:
	@pip-compile -o requirements.txt requirements.in