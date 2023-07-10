# nextcloud-ubi8-php
This container build is constructed with a recent Nextcloud source drop but layered on top of Apache 2.4/PHP 8.0 running on ubi8.

It has been built with OpenShift SCC restrictions in mind and as such will run non-prived and can be created
by a normal user in their project without cluster admin rights.

## Building images

You can easily build these images with podman eg:

```
podman build -f Containerfile.ubi8 -t quay.io/<you>/nextcloud-ubi8-php
podman push quay.io/<you>/nextcloud-ubi8-php
```
podman build -f Containerfile.ubi8 -t quay.io/<you>/nextcloud-ubi8-php

## Using images
There are some prebuilt images here:

* quay.io/agroom/nextcloud-ubi8-php
* quay.io/agroom/ubi-php80

## Installing on your OpenShift cluster

Should be able to use this container image within the nextcloud helm installer. Replace the standard image in the *values* file with the one built by executing podman above or referenceing the pre-built version in quay. For example see `../helmvalues`

## What's in the box?
The container is based on ubi8 and Apache/PHP 8.0. Layered on that is a version of Nextloud (See `NEXTCLOUD_VERSION`). Included with the images is scripts to launch or install Nextcloud on first use.

The PHP container want write access to its www tree. The source code is initially copied to `/opt/app-root/src` and this is is rsync to a writable zone /var/www/html on first use. If this is a PVC then the copy will persist. 

The scripts will install Nextcloud and its apps on first use and setup the database of choice.

The final patch up sets the httpd config to the new dynamic content root befire launching Apache HTTPD.

## Deprecated

Worth noting that both PHP 8.0 and Apache 2.4 are deprecated by Nextcloud. A better solution would be to upgrade to 81 and use MPM (fastCGI) probably using nginix. This is a work in progress in the ubi9 Containerfile. 

Note. Red Hat only supports PHP 8.1 on the ubi9 (RHEL 9) base and only with MPM

