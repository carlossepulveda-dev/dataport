# DataPort

Public DataPort releases and installation scripts.

DataPort packages are built and published to this repository by the release
workflow in the private DataPort source repository.

## Install Or Update DataPort

Choose the release channel required for the Raspberry Pi.

### Final

Use this channel for production. It requires a published final release:

```bash
curl --fail --silent --show-error --location https://raw.githubusercontent.com/carlossepulveda-dev/dataport/main/install-dataport-latest.sh | bash
```

### Release Candidate

Use this channel to test the next production release:

```bash
curl --fail --silent --show-error --location https://raw.githubusercontent.com/carlossepulveda-dev/dataport/main/install-dataport-rc.sh | bash
```

### Development

Use this channel only for active development testing:

```bash
curl --fail --silent --show-error --location https://raw.githubusercontent.com/carlossepulveda-dev/dataport/main/install-dataport-dev.sh | bash
```

Each installer:

- Selects only releases from its requested channel
- Downloads the matching `dataport_<version>_all.deb` release asset
- Installs or upgrades DataPort while preserving its data and configuration
- Allows an intentional downgrade when changing release channels

## Resolve Without Installing

Use `--dry-run` to print the resolved package download URL without downloading or
installing the package:

```bash
curl --fail --silent --show-error --location https://raw.githubusercontent.com/carlossepulveda-dev/dataport/main/install-dataport-latest.sh | bash -s -- --dry-run
curl --fail --silent --show-error --location https://raw.githubusercontent.com/carlossepulveda-dev/dataport/main/install-dataport-dev.sh | bash -s -- --dry-run
curl --fail --silent --show-error --location https://raw.githubusercontent.com/carlossepulveda-dev/dataport/main/install-dataport-rc.sh | bash -s -- --dry-run
```

Resolution diagnostics are printed to stderr. The resolved download URL is the
only value printed to stdout in dry-run mode.

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

## Release Channels

- `FINAL`: semantic version tags such as `v2.2.0`
- `RC`: prerelease tags such as `v2.2.0-rc.1`
- `DEV`: prerelease tags such as `v2.2.0-dev.1`

The FINAL installer exits without installing an RC or DEV build when no final
release has been published.

## Releases

Browse all releases:

https://github.com/carlossepulveda-dev/dataport/releases

## Support

If DataPort is already installed, running the appropriate channel command again
updates it to the newest release in that channel while preserving existing
configuration and data.

> **Note:** Only FINAL releases are supported for production deployments.
