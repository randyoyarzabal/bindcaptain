# BindCaptain Script Consolidation

## Problem

The original setup scripts had significant redundancy and were overly specific:

- **`setup.sh`** - User configuration setup (DNS zones, templates)
- **`setup-rocky9.sh`** - System preparation (Rocky 9 only, 337 lines)

### Issues Identified
1. **Overly specific**: Rocky 9 only, should support all DNF/YUM distros
2. **Redundant functionality**: Both checked prerequisites and did basic setup
3. **Confusing naming**: Unclear which script to use for what purpose
4. **Missing functionality**: No general Linux system setup script

## Solution

### New Script Structure

#### 1. `tools/system-setup.sh` (General System Setup)
- **Purpose**: Complete system preparation for BindCaptain
- **Scope**: All DNF/YUM-based distributions (RHEL, CentOS, Rocky, AlmaLinux, Fedora)
- **Functions**:
  - OS detection and compatibility checking
  - Package manager detection (dnf/yum)
  - System updates and prerequisite installation
  - Podman container runtime installation and configuration
  - Firewall configuration (firewalld)
  - SELinux configuration (if available)
  - BindCaptain installation from GitHub
  - Conflicting service detection and disabling
  - Basic testing

#### 2. `tools/config-setup.sh` (Configuration Setup)
- **Purpose**: User DNS configuration management
- **Scope**: Configuration templates and interactive setup
- **Functions**:
  - Prerequisites checking
  - User configuration directory setup
  - Template file copying
  - Interactive configuration wizard
  - Customized configuration generation

### Key Improvements

#### 1. **Distribution Support**
- **Before**: Rocky 9 only
- **After**: All DNF/YUM distributions (RHEL 8+, CentOS 8+, Rocky 8+, AlmaLinux 8+, Fedora)

#### 2. **Package Manager Detection**
```bash
# Auto-detect dnf or yum
if command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    PKG_INSTALL="dnf install -y"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
    PKG_INSTALL="yum install -y"
```

#### 3. **Clear Separation of Concerns**
- **System Setup**: Infrastructure, packages, services
- **Config Setup**: DNS zones, templates, user configuration

#### 4. **Better Error Handling**
- Graceful handling of missing tools (firewalld, SELinux)
- Clear error messages for unsupported distributions
- Fallback options for optional components

#### 5. **Improved User Experience**
- Clear script names indicating purpose
- Better help text and usage instructions
- Comprehensive logging

## Migration Guide

### For Users

#### Old Workflow
```bash
# Rocky 9 only
sudo ./tools/setup-rocky9.sh
sudo ./tools/setup.sh wizard
```

#### New Workflow
```bash
# All DNF/YUM distributions
sudo ./tools/system-setup.sh
sudo ./tools/config-setup.sh wizard
```

### For Developers

#### Script References
- Update any references from `setup.sh` to `config-setup.sh`
- Update any references from `setup-rocky9.sh` to `system-setup.sh`
- Use `system-setup.sh` for system-level operations
- Use `config-setup.sh` for configuration management

## File Changes

### Removed
- `tools/setup-rocky9.sh` (337 lines) - Rocky 9 specific

### Renamed
- `tools/setup.sh` → `tools/config-setup.sh` (201 lines)

### Added
- `tools/system-setup.sh` (350+ lines) - General system setup

### Updated
- `bindcaptain.sh` - Updated help text and references
- `README.md` - Updated quick start guide and script references

## Benefits

### 1. **Broader Compatibility**
- Supports all major RHEL-based distributions
- Auto-detects package manager
- Graceful handling of missing components

### 2. **Clearer Purpose**
- Script names clearly indicate their function
- Better separation of system vs configuration concerns
- Improved user experience

### 3. **Better Maintainability**
- Single system setup script for all distributions
- Reduced code duplication
- Easier to maintain and update

### 4. **Enhanced Functionality**
- Better error handling and user feedback
- More comprehensive logging
- Graceful degradation for optional components

## Testing

All scripts validated with bash syntax checking:
```bash
bash -n tools/system-setup.sh    # ✓ Pass
bash -n tools/config-setup.sh    # ✓ Pass
bash -n bindcaptain.sh           # ✓ Pass
```

## Usage Examples

### Complete Setup (New User)
```bash
# 1. Clone repository
git clone https://github.com/randyoyarzabal/bindcaptain.git
cd bindcaptain

# 2. System setup (installs Podman, configures system)
sudo ./tools/system-setup.sh

# 3. Configure DNS zones
sudo ./tools/config-setup.sh wizard

# 4. Build and run
sudo ./bindcaptain.sh build
sudo ./bindcaptain.sh run
```

### Configuration Only (Existing System)
```bash
# Just configure DNS zones
sudo ./tools/config-setup.sh wizard
```

### Manual Configuration
```bash
# Manual setup
sudo ./tools/config-setup.sh setup
# Edit files in user-config/
```

## Conclusion

The script consolidation successfully:
- ✅ Eliminated redundancy between setup scripts
- ✅ Expanded support to all DNF/YUM distributions
- ✅ Improved clarity with better script names
- ✅ Enhanced functionality and error handling
- ✅ Maintained backward compatibility for core functionality

The new structure provides a cleaner, more maintainable codebase while supporting a broader range of Linux distributions.
