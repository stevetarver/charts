This repo hosts personal helm charts published through gh-pages through the `docs` directory as described in [GitHub documentation](https://github.com/kubernetes/helm/blob/master/docs/chart_repository.md).

## Use

To use this repo:

```
ᐅ helm repo add makara-stable https://stevetarver.github.io/charts
"makara-stable" has been added to your repositories
ᐅ helm repo list
NAME         	URL
stable       	https://kubernetes-charts.storage.googleapis.com
local        	http://127.0.0.1:8879/charts
makara-stable	https://stevetarver.github.io/charts
```

## Maintenance

A robust repo would have some kind of automation to package charts on git commit; for now we'll do this manually. After testing chart changes, prior to the commit, adjust version numbers and package each affected helm chart:

```
ᐅ cd docs
ᐅ helm package ../stable/jenkins
Successfully packaged chart and saved it to: /Users/starver/code/makara/charts/docs/jenkins-1.0.0.tgz
ᐅ helm repo index ./ --url https://stevetarver.github.io/charts
ᐅ ll
total 24
-rwxr-xr-x  1 starver  staff   384B Jul  3 11:46 index.yaml
-rw-r--r--  1 starver  staff   6.8K Jul  3 11:45 jenkins-1.0.0.tgz
```

