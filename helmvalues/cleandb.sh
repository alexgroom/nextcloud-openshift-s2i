
#clean db
mysql --user=nextcloud --password=nextcloud --host=nextclouddb --execute="use nextcloud; drop database nextcloud; show databases;" nextcloud

# clean db
oc rsh nextclouddb-XXXX mysql --user=nextcloud --password=nextcloud --host=nextclouddb --execute="use nextcloud; drop database nextcloud; show databases;" nextcloud