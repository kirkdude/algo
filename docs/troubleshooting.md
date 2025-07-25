# Troubleshooting Guide

This document tracks known issues and their solutions for the Algo VPN project.

## Current Issues (as of 2025-07-25)

### 1. GitHub Actions Network Dependency Failures

**Status**: FIXED (2025-07-25)

**Problem**: GitHub Actions failing with DNS resolution errors for Ubuntu package repositories:
- `Temporary failure resolving 'archive.ubuntu.com'`
- `Temporary failure resolving 'security.ubuntu.com'`
- Package installation failures for `python3-virtualenv`, `python3-pip`
- LXC container "Error: Not Found" when pushing files

**Root Cause**: Network connectivity issues in CI environment preventing package updates and dependency installation.

**Solution Applied**:
- Added reliable DNS servers (8.8.8.8, 1.1.1.1) to LXC containers
- Implemented timeout and retry logic for apt operations
- Fixed directory creation order to ensure target paths exist before file operations
- Pre-stage repository before attempting package installation

**Files Modified**:
- `tests/pre-deploy.sh`: Lines 35, 45-51, 57

**Previous Attempts**:
- Hard-coded DNS settings (removed later due to cycling issues)
- Various network configuration attempts

### 2. Test Kitchen SSH Connectivity Timeout

**Status**: ACTIVE INVESTIGATION (2025-07-25)

**Problem**: VM creates successfully but SSH service fails to start or respond on assigned port:
```
Waiting for SSH service on 127.0.0.1:2204, retrying in 3 seconds
```

**Root Cause**: SSH daemon not starting properly in Ubuntu 24.04 VMs, causing infinite retry loop. **REGRESSION** - this configuration worked previously before GitHub Actions fixes.

**Affected Instances**:
- `quantum-safe-strongswan-only-ubuntu-2404` - SSH timeout on port 2204
- Retries for 30+ minutes without success

**Analysis**:
- VM creation succeeds: "Machine not provisioned because `--no-provision` is specified"
- Port assignment works: 2222 → 2204 collision resolution
- SSH service fails to start or bind to expected port
- Issue specific to `bento/ubuntu-24.04` base box

**Current Investigation Status**:
- VM boots completely but SSH connectivity fails
- Other instances (ubuntu-22.04) work normally
- May be related to systemd SSH service configuration in newer Ubuntu versions

**Potential Solutions**:
1. **Switch base box**: Try `ubuntu/noble64` instead of `bento/ubuntu-24.04`
2. **Add SSH debug**: Configure Vagrant with explicit SSH settings
3. **Check systemd**: Investigate SSH service status in the VM
4. **Network config**: Verify port forwarding and firewall settings
5. **Resource limits**: Check if multiple VMs are exhausting system resources

**Immediate Action**: Test with alternative base box configuration

### 3. Test Kitchen Script Errors

**Status**: IDENTIFIED - MINOR

**Problem**: Shell script compatibility issue in Test Kitchen provisioner:
```
/tmp/kitchen/install_script: 66: [[: not found
```

**Root Cause**: Script using bash-specific `[[` syntax but running under dash/sh.

**Impact**: Low - doesn't prevent installation, just generates warnings.

**Solution**: Update omnibus-ansible install script to use POSIX-compliant syntax or ensure bash execution.

## Historical Issues

### DNS Resolution in LXC Containers (RESOLVED)

**Problem**: LXC containers couldn't resolve external hostnames for package installation.

**Solution**:
- Set explicit DNS servers in `/etc/resolv.conf`
- Added timeout and retry logic for network operations

### File Transfer Path Issues (RESOLVED)

**Problem**: LXC file push operations failing with "Error: Not Found"

**Solution**:
- Ensure target directories exist before file operations
- Fixed operation order in `tests/pre-deploy.sh`

## Investigation Methodology

When troubleshooting new issues:

1. **Check logs**: Always start with detailed log analysis
   - GitHub Actions: `logs/` directory
   - Test Kitchen: `.kitchen/logs/` directory

2. **Identify patterns**: Look for common error messages across different runs

3. **Test isolation**: Determine if issues are environment-specific or code-specific

4. **Document findings**: Update this file with discoveries to prevent state loss

5. **Version changes**: Note any dependency or environment changes that might cause regressions

## Debugging Commands

### Test Kitchen
```bash
# Clean state and retry
kitchen destroy
kitchen converge

# Verbose debugging
kitchen converge --log-level debug

# Check configuration
kitchen diagnose --all
```

### GitHub Actions Local Testing
```bash
# Run equivalent commands locally
make ci-simple
make ci-local
```

### LXC Container Debugging
```bash
# Check container state
lxc list
lxc exec algo -- systemctl status
lxc exec algo -- ping -c 3 8.8.8.8
lxc exec algo -- nslookup github.com
```

## Next Steps

1. **VirtualBox/Vagrant timeout**: Implement boot timeout increase and Guest Additions update
2. **Resource optimization**: Consider reducing parallel VM creation to avoid resource contention
3. **Alternative testing**: Evaluate Docker-based testing as backup to VirtualBox
4. **Monitoring**: Add more detailed logging to identify bottlenecks in VM provisioning
