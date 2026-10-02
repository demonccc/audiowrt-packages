# Pending package build state

Automatic package publication is driven by the last successfully published package/context state, not only by the immediately previous Git commit.

A package/context is pending when:

- it has never been successfully published for the channel;
- its package source changed after its last successful publication;
- an explicitly declared rebuild dependency changed after its last successful publication;
- an architecture-, target-, or OpenWrt-release-specific patch applicable to that context changed after its last successful publication.

Failed package/context builds remain pending on the next merge. Successful sibling contexts keep their published state and are not rebuilt unless their effective inputs change.

GitHub Actions groups all pending tasks for the same OpenWrt release and package architecture into one matrix job. This keeps the number of runners bounded by the architecture matrix while preserving incremental package builds inside each runner.
