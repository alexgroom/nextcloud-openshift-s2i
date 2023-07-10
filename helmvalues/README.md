# Helm Values
Here are some helm "values" that work with the Nextcloud helm chart installer: https://github.com/nextcloud/helm.git

## Database
The helm values assume that a MariaDB already has been provisioned in the project with the following attributes:

* Service nextclouddb
* Name nextcloud
* Password nextcloud
* Database nextcloud

The helm chart also supports PostgresSQL but that has not been tested here.

## Deploy
Deploy the helm chart as follows (adding the expose to get a Route)

```
helm repo add nextcloud https://nextcloud.github.io/helm/
helm install <nextcloud> nextcloud/nextcloud -f ../nextcloud-openshift-s2i/helmvalues/devSandbox.yaml 
oc expose svc/<nextcloud>
```

## Adding a secure route
Easiets way to get a secure route is to use the OpenShift Edge route mode where the TSL is terminated at the OpenShift edge
and HTTP is used across the OpenShift. This can be improved I'm sure with the use of local certs.

```
oc create route edge <nextcloud-route> --name <nextcloud> --port 8080
```

Note that if you get warnings from Nextcloud UI about trusted domains then you need to correctly configure the host in the values.yaml file for example:

I'd like to think that a domain wildcard also works such as just: `apps.sandbox-m4.g2pi.p1.openshiftapps.com`

```
nextcloud:
  host: nextcloud-agroom-dev.apps.sandbox-m4.g2pi.p1.openshiftapps.com
```

## Cleaning up the database

Uninstall:

```
helm uninstall <nextcloud>
```

To clean (drop) the Maria db, use a script like this:

```
oc get pods
oc rsh <nextclouddb-pod-XXXX> mysql --user=nextcloud --password=nextcloud --host=nextclouddb --execute="use nextcloud; drop database nextcloud; show databases;" nextcloud
```