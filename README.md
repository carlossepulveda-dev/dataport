# DataPort

DataPort Installer Repository.

## Install or Update DataPort

Run the following command on the Raspberry Pi:

```bash
curl -sSL https://raw.githubusercontent.com/carlossepulveda-dev/dataport/main/install-dataport-latest.sh | bash
```

This command automatically:

* Downloads the latest DataPort release
* Installs or upgrades DataPort
* Updates to the newest available version

## Verify Service

```bash
systemctl status dataport
```

## Access DataPort

```text
https://dataport.local
```

Download Root Certificate to validate SSL

```text
http://dataport.local/downloads/DataPortRootCA.crt
```

## Latest Release

Browse all releases:

https://github.com/carlossepulveda-dev/dataport/releases
