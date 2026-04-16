#!/bin/bash
IDS=$(curl -s -u gitea-admin:Gitea@Admin2024! http://gitea.local/api/v1/repos/gitops/order-api/hooks | grep -o '"id":[0-9]*' | cut -d':' -f2)
for id in $IDS; do
  echo "Deleting hook $id"
  curl -s -X DELETE -u gitea-admin:Gitea@Admin2024! http://gitea.local/api/v1/repos/gitops/order-api/hooks/$id
done
