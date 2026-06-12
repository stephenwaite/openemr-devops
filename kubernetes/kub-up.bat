@echo off

kubectl wait --for=condition=Ready nodes --all --timeout=120s

kubectl apply ^
    -f nfs/rbac.yaml ^
    -f nfs/storageclass.yaml ^
    -f nfs/service.yaml ^
    -f nfs/deployment.yaml
timeout 30

kubectl apply --validate=false -f https://github.com/cert-manager/cert-manager/releases/download/v1.20.2/cert-manager.yaml
kubectl wait --for=condition=Available --timeout=120s -n cert-manager deployment/cert-manager-webhook
timeout 15

kubectl apply ^
    -f certs/selfsigned-issuer.yaml ^
    -f certs/ca-certificate.yaml ^
    -f certs/ca-issuer.yaml ^
    -f certs/mysql.yaml ^
    -f certs/mysql-replication.yaml ^
    -f certs/mysql-openemr-client.yaml ^
    -f certs/phpmyadmin.yaml ^
    -f certs/mysql-phpmyadmin-client.yaml ^
    -f certs/redis.yaml ^
    -f certs/redis-openemr-client.yaml ^
    -f certs/sentinel.yaml
timeout 15

kubectl apply ^
    -f mysql/configmap.yaml ^
    -f mysql/secret.yaml ^
    -f mysql/replication-secret.yaml ^
    -f mysql/service.yaml ^
    -f mysql/statefulset.yaml ^
    -f redis/secret.yaml ^
    -f redis/configmap-main.yaml ^
    -f redis/configmap-acl.yaml ^
    -f redis/statefulset-redis.yaml ^
    -f redis/statefulset-sentinel.yaml ^
    -f redis/service-redis.yaml ^
    -f redis/service-sentinel.yaml ^
    -f phpmyadmin/configmap.yaml ^
    -f phpmyadmin/deployment.yaml ^
    -f phpmyadmin/service.yaml ^
    -f volumes/letsencrypt.yaml ^
    -f volumes/ssl.yaml ^
    -f volumes/website.yaml ^
    -f openemr/secret.yaml ^
    -f openemr/deployment.yaml ^
    -f openemr/service.yaml ^
    -f network/policies.yaml
