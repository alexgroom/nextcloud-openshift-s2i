# Helm Values
Here are some helm "values" that work with the Nextcloud helm chart installer: https://github.com/nextcloud/helm.git

## Database
The helm values assume that a (bitnami) MariaDB is provisioned as a StatefulSet alongside the nextcloud instance

The helm chart also supports PostgresSQL but that has not been tested here.

## Deploy
Deploy the helm chart as follows (adding the expose to get an http Route)

```
helm repo add nextcloud https://nextcloud.github.io/helm/
helm install <nextcloud> nextcloud/nextcloud -f ../nextcloud-openshift-s2i/helmvalues/devSandbox.yaml 
oc expose svc/<nextcloud>
```

## Adding a secure route
Easiest way to get a secure route is to use the OpenShift Edge route mode where the TSL is terminated at the OpenShift edge
and HTTP is used across the OpenShift. This can be improved I'm sure with the use of local certs.

```
oc create route edge <nextcloud-route> --name <nextcloud> --port 8080
```

Note that if you get warnings from Nextcloud UI about trusted domains then you need to correctly configure the host in the values.yaml file and redeploy, for example for RH Sandbox
```
nextcloud:
  host: nextcloud-agroom-dev.apps.sandbox-m4.g2pi.p1.openshiftapps.com
```

However, this fixed value is incredibly inconvenient since you need to create the value to exactly match the route (and project and helm deployment name) so to make it more universal you can use wildcards, however, the helm chart gets very confused with leading *
so we fix this up by expliciting defining the ENV value NEXTCLOUD_TRUSTED_DOMAINS further down in the values.yaml file. 

So the values file has been configured for a generic Sandbox solution like this:

```
 extraEnv:
  #  - name: SOME_SECRET_ENV
  #    valueFrom: 
  #      secretKeyRef:
  #        name: nextcloud 
  #        key: secret_key
    - name: NEXTCLOUD_TRUSTED_DOMAINS
      value: "*.p1.openshiftapps.com"
```

Now to deploy in your cluster, the wildcard string will likely be very different. So change the TRUSTED_DOMAINS value accordingly, at a guess `*.apps.<yourcluster>`
might work.

## Cleaning up

Uninstall:

```
helm uninstall <nextcloud>
```

Note that the maridb storage may need to be manually destroyed.

To clean (drop) the Maria db, use a script like this:

```
oc get pods
oc rsh <nextclouddb-pod-XXXX> mysql --user=nextcloud --password=nextcloud --host=nextclouddb --execute="use nextcloud; drop database nextcloud; show databases;" nextcloud
```
