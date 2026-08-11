# Shared workaround flags for this machine's CLT modulemap bug.
SCRATCH=/private/tmp/claude-501/-Users-samuelbesley-Autoclicker/ec2d7f7a-c98d-4383-9792-d13f930706b9/scratchpad
SWIFT_FLAGS=(-swift-version 5 -target arm64-apple-macos13.0 -module-cache-path $SCRATCH/mcache -vfsoverlay $SCRATCH/overlay.yaml -Xcc -ivfsoverlay -Xcc $SCRATCH/overlay.yaml)
