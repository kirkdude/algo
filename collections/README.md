# Ansible Collections

This directory contains Ansible collection requirements for the Algo VPN project.

## Collection Compatibility

The `requirements.yml` file specifies version ranges for Ansible collections that are compatible with different versions of ansible-core:

- **ansible-core 2.13+**: Compatible with the specified collection versions
- **ansible-core 2.16+**: Required for the main `requirements.txt` (ansible==9.1.0)

## Installing Collections

To install the collections with compatible versions:

```bash
ansible-galaxy collection install -r collections/requirements.yml
```

## Version Warnings

If you see warnings like:

```text
[WARNING]: Collection community.general does not support Ansible version 2.13.10
```

This means your local ansible-core version is older than what the installed collections expect. The playbooks will still work for syntax checking and basic operations, but for full functionality, consider:

1. Upgrading to Python 3.9+ and installing `ansible==9.1.0`
2. Using the Docker deployment method
3. Ignoring the warnings for development (they don't affect syntax validation)

The warnings are informational and don't prevent syntax checking or most operations.
