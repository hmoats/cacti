# cacti

Collection of scripts and information regarding the installation of cacti version `cacti-0.8.8h`. I use this older version becasue I'm very fond of the weathermap plugin which I believe provides the easiest way to see traffic patterns in your environment. At the time of this document, weathermap is not easily installed with cacti version >= 1.0. This may have changed but generally most of the functionality that I like to use is in pre 1.0 versions.

```
.
├── cacti-0.8.8h.tar.gz
├── cacti-backup.sh
├── cacti-install.sh
├── cacti-restore.sh
├── cacti-spine-0.8.8h.tar.gz
├── images
├── network-weathermap-version-0.98a.tar.gz
├── README.md
├── settings-v0.71-1.tgz
├── superlinks-v1.4-2.tgz
└── thold-v0.5.0.tgz
```

## Installation

- Step 1: clone this repository into /opt/cacti (if you need to install this somewhere else update all the scripts to reflect your environment.)
- Step 2: run `cacti-backup.sh` and hope there are no errors :)
- Step 3: point your web browser at your service and then login as admin/admin (default account)
- Step 4: enable spine poller
![enable spine](images/cacti-enable-spine.PNG)