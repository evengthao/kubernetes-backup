#!/bin/bash -e

# require pip install PyYAML to be installed
# passing in context and path
kubectl config use-context $0
NAMESPACES=$(kubectl get ns -o jsonpath={.items[*].metadata.name})



#RESOURCETYPES="${RESOURCETYPES:-"ingress deployment configmap svc rc ds networkpolicy statefulset cronjob pvc secrets hpa"}"
RESOURCETYPES="ingress deployment configmap svc rc ds networkpolicy statefulset cronjob pvc secrets hpa"
GLOBALRESOURCES="namespace storageclass clusterrole clusterrolebinding customresourcedefinition"

echo 

GIT_REPO_PATH=$1
GIT_PREFIX_PATH="${GIT_PREFIX_PATH:-"."}"

mkdir -p "$GIT_REPO_PATH/$GIT_PREFIX_PATH"

echo "$GIT_REPO_PATH/$GIT_PREFIX_PATH"
cd "$GIT_REPO_PATH/$GIT_PREFIX_PATH"

# Start kubernetes state export
for resource in $GLOBALRESOURCES; do
    [ -d "$GIT_REPO_PATH/$GIT_PREFIX_PATH" ] || mkdir -p "$GIT_REPO_PATH/$GIT_PREFIX_PATH"
    echo "Exporting resource: ${resource}" >/dev/stderr
    kubectl get -o=json "$resource" | jq --sort-keys \
        'del(
          .items[].metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
          .items[].metadata.annotations."control-plane.alpha.kubernetes.io/leader",
          .items[].metadata.uid,
          .items[].metadata.selfLink,
          .items[].metadata.resourceVersion,
          .items[].metadata.creationTimestamp,
          .items[].metadata.generation
      )' | python -c 'import sys, yaml, json; yaml.safe_dump(json.load(sys.stdin), sys.stdout, default_flow_style=False)' >"$GIT_REPO_PATH/$GIT_PREFIX_PATH/${resource}.yaml"
done

for namespace in $NAMESPACES; do
    [ -d "$GIT_REPO_PATH/$GIT_PREFIX_PATH/${namespace}" ] || mkdir -p "$GIT_REPO_PATH/$GIT_PREFIX_PATH/${namespace}"

    for type in $RESOURCETYPES; do
        echo "[${namespace}] Exporting resources: ${type}" >/dev/stderr

        label_selector=""
        if [[ "$type" == 'configmap' && -z "${INCLUDE_TILLER_CONFIGMAPS:-}" ]]; then
            label_selector="-l OWNER!=TILLER"
        fi

        kubectl --namespace="${namespace}" get "$type" $label_selector -o custom-columns=SPACE:.metadata.namespace,KIND:..kind,NAME:.metadata.name --no-headers | while read -r a b name; do
            [ -z "$name" ] && continue

        # Service account tokens cannot be exported
        # if [[ "$type" == 'secret' && $(kubectl get -n "${namespace}" -o jsonpath="{.type}" secret "$name") == "kubernetes.io/service-account-token" ]]; then
        #     continue
        # fi

        kubectl --namespace="${namespace}" get -o=json "$type" "$name" | jq --sort-keys \
        'del(
            .metadata.annotations."control-plane.alpha.kubernetes.io/leader",
            .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
            .metadata.creationTimestamp,
            .metadata.generation,
            .metadata.resourceVersion,
            .metadata.selfLink,
            .metadata.uid,
            .spec.clusterIP,
            .status
        )' | python -c 'import sys, yaml, json; yaml.safe_dump(json.load(sys.stdin), sys.stdout, default_flow_style=False)' >"$GIT_REPO_PATH/$GIT_PREFIX_PATH/${namespace}/${name}.${type}.yaml"
        done
    done
done

cd "${GIT_REPO_PATH}"

kubectl get deployments -o=custom-columns=NAME:.metadata.name > kubernetes-deployment-list.txt

git add .

if ! git diff-index --quiet HEAD --; then
    git commit -m "Automatic backup at $(date)"
else
    echo "No change"
fi

cd ..
