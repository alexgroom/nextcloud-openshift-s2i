# nextcloud-ubi8-php
This container build is constructed with a recent Nextcloud source but layered on top of PHP 8.0 running on ubi8.
It has been built with OpenShift SCC restrictions in mind and as such will run non-prived and can be created
by a normal user in their project without Admin rights.

# ubi-php

Container images based on the [SCL PHP image](https://github.com/sclorg/s2i-php-container).
Built to include additional or updated packages like redis, delivered or compiled
outside the default & official repositories available within the distribution.

You can use this as a base for the S2I code included in this repo: 
```
oc new-app quay.io/agroom/ubi8-php80:latest~https://github.com/alexgroom/nextcloud-openshift-s2i.git --name nextcloud-ocp-s2i-afg
```

## Building images

You can easily build these images with podman eg:

```
$ podman build -f Containerfile.ubi8 -t quay.io/<you>/nextcloud-ubi8-php
```

## Images Available:

A set of images are available here (for x86_64):

* quay.io/agroom/nextcloud-ubi8-php
* quay.io/agroom/ubi-php80

## Installing on your OpenShift cluster

Should be able to use this container image within the nextcloud helm installer. Replace the standard image in the *values* file with the one built by executing podman above or referenceing the pre-built version in quay.

