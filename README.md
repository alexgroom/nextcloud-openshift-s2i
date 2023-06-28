# nextcloud-openshift-s2i
Get NextCloud ready to run on OpenShift with 
[S2I](https://docs.openshift.com/container-platform/latest/builds/understanding-image-builds.html#build-strategy-s2i_understanding-image-builds)

## Quick Start

$ oc new-app quay.io/agroom/ubi8-php80~https://github.com/cuppett/nextcloud-openshift-s2i.git

    --> Found container image 328ff90 (2 hours old) from quay.io for "quay.io/agroom/ubi8-php80"
    
        Apache 2.4 with PHP 8.0 
        ----------------------- 
        PHP 8.0 available as container is a base platform for building and running various PHP 8.0 applications and frameworks. PHP is an HTML-embedded scripting language. PHP attempts to make it easy for developers to write dynamically generated web pages. PHP also offers built-in database integration for several commercial and non-commercial database management systems, so writing a database-enabled webpage with PHP is fairly simple. The most common use of PHP coding is probably as a replacement for CGI scripts.
    
        Tags: builder, php, php80, php-80
    
        * An image stream tag will be created as "ubi8-php:74" that will track the source image
        * A source build using source code from https://github.com/cuppett/nextcloud-openshift-s2i.git will be created
          * The resulting image will be pushed to image stream tag "nextcloud-openshift-s2i:latest"
          * Every time "ubi8-php:74" changes a new build will be triggered
    
    --> Creating resources ...
    imagestream.image.openshift.io "ubi8-php" created
    imagestream.image.openshift.io "nextcloud-openshift-s2i" created
    buildconfig.build.openshift.io "nextcloud-openshift-s2i" created
    deployment.apps "nextcloud-openshift-s2i" created
    service "nextcloud-openshift-s2i" created
    --> Success
    Build scheduled, use 'oc logs -f buildconfig/nextcloud-openshift-s2i' to track its progress.
    Application is not exposed. You can expose services to the outside world by executing one or more of the commands below:
    'oc expose service/nextcloud-openshift-s2i'
    Run 'oc status' to view your app.
    
$ oc expose service/nextcloud-openshift-s2i
    
    route.route.openshift.io/nextcloud-openshift-s2i exposed

$ oc patch route/nextcloud-openshift-s2i --type=merge --patch='{"spec":{"tls":{"termination":"edge"}}}'

    route.route.openshift.io/nextcloud-openshift-s2i patched


## Digging Deeper

### Environment Variables

The container built from this repository contains many of the same environment automatic configuration
capabilities as the 
[official Nextcloud image](https://github.com/nextcloud/docker#auto-configuration-via-environment-variables).
Please see that repository for a dive into those.

Specifically, these may need some tweaking depending on your deployment (but others may as well):

| Name               | Example Value                           |
| :-------------     | :----------                             |
| OVERWRITEPROTOCOL  | https                                   | 
| TRUSTED_PROXIES    | 172.16.0.0/12 10.0.0.0/8 192.168.0.0/16 |

### Cron

By default, cron is configured to run on every page load via AJAX.
Within OpenShift/Kubernetes, it is possible to handle
this with 
[CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/).
Please see the 
[admin guide](https://docs.nextcloud.com/server/20/admin_manual/configuration_server/background_jobs_configuration.html)
for additional information.

Here is an example from OpenShift using [UBI](https://www.redhat.com/en/blog/introducing-red-hat-universal-base-image):

```yaml 
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: nextcron
spec:
  concurrencyPolicy: Allow
  failedJobsHistoryLimit: 1
  jobTemplate:
    metadata:
      creationTimestamp: null
    spec:
      template:
        metadata:
          creationTimestamp: null
        spec:
          containers:
          - args:
            - curl
            - https://<< YOUR_NEXTCLOUD_ROUTE_URL >>/cron.php
            image: registry.access.redhat.com/ubi8
            imagePullPolicy: Always
            name: cron
            resources: {}
            terminationMessagePath: /dev/termination-log
            terminationMessagePolicy: File
          dnsPolicy: ClusterFirst
          restartPolicy: Never
          schedulerName: default-scheduler
          securityContext: {}
          terminationGracePeriodSeconds: 30
  schedule: '*/5 * * * *'
  successfulJobsHistoryLimit: 3
  suspend: false

```
