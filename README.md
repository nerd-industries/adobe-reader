# adobe-reader

Silently install the latest **Adobe Acrobat Reader (64-bit)** on a Windows PC
with **no McAfee, Norton or other bundled offers**, and without Adobe's upsell
and AI Assistant pop-ups.

Served via Cloudflare Pages at **https://reader.nerdyneighbor.net** so the latest
committed version always runs.

## Run it (elevated Windows PowerShell)

```powershell
irm reader.nerdyneighbor.net | iex
```

No options. It's non-interactive, so it's safe to run from RMM / SuperOps.
It's also in the toolkit menu: `irm toolkit.nerdyneighbor.net | iex`.

## What it does

1. **Already have Acrobat or Reader?** It stops and changes nothing. Paid Acrobat
   Pro shows up in Windows under the same name as Reader, so we don't touch it.
2. Asks Adobe's download service (the one get.adobe.com uses) for the latest
   Reader version. Nothing is pinned, so it always gets the current release.
3. Downloads Adobe's **offline enterprise installer** (about 750 MB) straight
   from `ardownload2.adobe.com`. The McAfee/Norton offers only ever come with the
   small web installer on get.adobe.com, so this one has none.
4. **Checks the file's digital signature** and only runs it if it's validly
   signed by Adobe Inc.
5. Installs silently: `/sAll /rs /msi EULA_ACCEPT=YES` (no UI, no reboot).
6. Cleans it up:
   - `bAcroSuppressUpsell = 1`: no "upgrade to Acrobat Pro" or trial pop-ups.
   - `bEnableGentech = 0`: no AI Assistant. This also means documents aren't
     sent to Adobe's AI servers.
   - Removes the Acrobat extension that the installer pushes into Chrome and Edge.
7. Deletes the installer and logs to `C:\ProgramData\NerdyNeighbor\reader.log`.

Adobe's own updater stays on, so Reader keeps getting security fixes.

## Caveats

- 64-bit Windows only. Current Reader doesn't support 32-bit Windows.
- Needs about 3 GB free on the system drive while installing.
- Installs English (`en_US`). Other languages need the `_MUI` installer.
- To remove it: Settings > Apps > **Adobe Acrobat (64-bit)** > Uninstall.
- If the PC already has McAfee or Norton from an old Adobe install, use the
  "Remove third-party antivirus" toolkit option (`avremove.nerdyneighbor.net`).
