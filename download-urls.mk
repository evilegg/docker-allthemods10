# download-urls.mk — version registry
#
# To add a new release:
#   1. Copy the block template below and fill in the four fields.
#   2. Update DEFAULT_VERSION to point at the new entry.
#   3. Run `make <name>` to build locally or `make dist-<name>` to push.
#
# Block template:
#
#   VERSIONS             += 10-X.Y
#   VERSION_SRV_10-X.Y   := X.Y
#   VERSION_FILE_10-X.Y  := <curseforge file id>
#   VERSION_NF_10-X.Y    := <neoforge version>
#   DOWNLOAD_URL_<fileid> := <direct download url for Server-Files-X.Y.zip>
#
# File IDs and download URLs are on the CurseForge file page:
#   https://www.curseforge.com/minecraft/modpacks/all-the-mods-10/files/<fileid>
#
# NeoForge versions are listed at:
#   https://maven.neoforged.net/#releases/net/neoforged/neoforge

DEFAULT_VERSION := 10-6.1

VERSIONS :=

# ── 5.5 (2024-09-xx) ──────────────────────────────────────────────────────────
VERSIONS            += 10-5.5
VERSION_SRV_10-5.5   := 5.5
VERSION_FILE_10-5.5  := 7558573
VERSION_NF_10-5.5    := 21.1.219
DOWNLOAD_URL_7558573 := https://curseforge.com/minecraft/modpacks/all-the-mods-10/files/7558573/Server-Files-5.5.zip

# ── 6.0.1 (2024-11-xx) ────────────────────────────────────────────────────────
VERSIONS              += 10-6.0.1
VERSION_SRV_10-6.0.1  := 6.0.1
VERSION_FILE_10-6.0.1 := 7676054
VERSION_NF_10-6.0.1   := 21.1.219
DOWNLOAD_URL_7676054  := https://curseforge.com/minecraft/modpacks/all-the-mods-10/files/7676054/Server-Files-6.0.1.zip

# ── 6.1 (2025-01-xx) ──────────────────────────────────────────────────────────
VERSIONS            += 10-6.1
VERSION_SRV_10-6.1   := 6.1
VERSION_FILE_10-6.1  := 7722629
VERSION_NF_10-6.1    := 21.1.219
DOWNLOAD_URL_7722629 := https://curseforge.com/minecraft/modpacks/all-the-mods-10/files/7722629/Server-Files-6.1.zip
