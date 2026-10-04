# Canonical package build ownership

Package compilation in this repository delegates to the proven package-mode build in `demonccc/audiowrt`.

The AudioWRT repository is the canonical owner of OpenWrt SDK preparation, exact-release feed selection, AudioWRT dependency ordering, development-interface staging, trimmed kernel module preparation, hostap/wpa build preparation, and native player build preparation.

This repository owns package source code, pending-build planning, architecture fan-out, release creation, repository-update metadata, and incremental publication.

The publish workflow pins the canonical build engine to commit `680f766ac513d3c9bdcc6ea04f20ac0b8f59b207`. Update that pin deliberately when the canonical package build model changes.
