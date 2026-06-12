# DataPort

DataPort Installer Repository.

## Install or Update DataPort (Stable Release)

Run the following command on the Raspberry Pi:

```bash
curl -sSL https://raw.githubusercontent.com/carlossepulveda-dev/dataport/main/install-dataport-latest.sh | bash
```

This command automatically:

- Downloads the latest stable DataPort release
- Installs or upgrades DataPort
- Updates to the newest production version

## Verify Service

```bash
systemctl status dataport
```

## Access DataPort

Open DataPort in your browser:

```text
https://dataport.local
```

## Install SSL Root Certificate

Download the DataPort Root Certificate:

```text
http://dataport.local/downloads/DataPortRootCA.crt
```

After downloading:

1. Open the certificate file.
2. Install it into the system's Trusted Root Certificate Store.
3. Restart the browser if required.

## Releases

Browse all releases:

https://github.com/carlossepulveda-dev/dataport/releases

## Support

If DataPort is already installed, running the installation command again will safely upgrade the system to the latest stable version while preserving existing configuration and data.

>  **Note:** Only stable releases are supported for production deployments.
