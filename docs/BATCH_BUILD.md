# Batch package builds

Automatic package builds are grouped by architecture and by OpenWrt target/subtarget context.

Within each context the SDK is prepared once, feeds are indexed once, and all pending AudioWRT package compile targets are passed to one `make` invocation. This avoids rebuilding shared OpenWrt dependencies repeatedly for each AudioWRT package.
