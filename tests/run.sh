#!/usr/bin/env bash
set -euo pipefail

echo "======================================================"
echo " Running NixOS Configuration Tests"
echo "======================================================"

# 1. 运行静态配置断言测试
echo ">> [1/3] Running Static Evaluation Check..."
nix-build tests/static.nix --no-out-link

# 2. 运行全自动安装 ISO 评估测试
echo ">> [2/3] Running Installer ISO Static Check..."
nix-build tests/installer.nix --no-out-link

# 3. 运行 VM 测试（如果支持 KVM 或在 CI 环境中）
if [ -e /dev/kvm ]; then
  echo ">> [3/3] Running NixOS VM Test (KVM enabled)..."
  nix-build tests/vmtest.nix --no-out-link
else
  echo ">> [3/3] /dev/kvm not found. Skipping VM test in non-KVM environment."
fi

echo "======================================================"
echo " All tests passed successfully!"
echo "======================================================"
