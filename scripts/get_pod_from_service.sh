if ! [ -z $1 ]; then
    SERVICE_NAME="$1"
fi

if [ -z "${SERVICE_NAME}" ]; then
    echo "SERVICE_NAME is empty. Exiting."
    echo "Try ./get_pod_from_service.sh ml-pipeline-ui"
    exit 1
fi

kubectl get pods --selector="app=${SERVICE_NAME}" \
    --no-headers \
    --output custom-columns=":metadata.name"