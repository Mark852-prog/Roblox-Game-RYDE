# Getting Started (for complete beginners)

This guide gets the game running on your computer. You do **not** need to
write any code. It takes about 15 minutes the first time.

---

## A few words you will see

| Word | What it means |
|---|---|
| **Roblox Studio** | The free program used to build Roblox games. It is separate from the normal Roblox player app. |
| **Place file (`.rbxl`)** | One file that contains a whole Roblox game: the map, the scripts, the settings. `build/RYDE.rbxl` is ours. |
| **Explorer** | A Studio panel that lists everything in the game as a tree, like folders on your computer. |
| **Properties** | A Studio panel that shows the settings of whatever you clicked in the Explorer. |
| **Output** | A Studio panel where scripts print messages and errors. This is where you look when something is wrong. |
| **Script** | Code that runs on the **server** (the game's "referee"; it decides what really happens). |
| **LocalScript** | Code that runs on each **player's own device** (input, camera, screen UI). |
| **ModuleScript** | A piece of code that other scripts load and share, e.g. the bike settings. |
| **ReplicatedStorage** | A place in the game tree that both the server and players can see. Our shared code and settings live here. |
| **ServerScriptService** | Where server Scripts live. Players can't see or change them. |
| **StarterPlayer** | Contains scripts that get copied to each player when they join. |
| **Workspace** | The 3D world: the map, players, vehicles. |
| **Stud** | Roblox's unit of length. In this game, 1 stud = 0.35 metres. |

---

## Step 1 — Install Roblox Studio

1. Go to <https://create.roblox.com/> and sign in with your Roblox account.
2. Click **Start Creating** (or **Download Studio**) and run the installer.
3. Open **Roblox Studio** once and sign in. Close any tutorial pop-ups.

✅ You're done with this step when Studio shows its start page with templates like "Baseplate".

## Step 2 — Download the game file

You only need one file: `build/RYDE.rbxl`.

1. Open this link in your web browser (you must be signed in to GitHub):
   **https://github.com/Mark852-prog/Roblox-Game-RYDE/raw/claude/quirky-darwin-t7u0nt/build/RYDE.rbxl**
2. The browser downloads `RYDE.rbxl` (about 30 KB) — usually into your **Downloads** folder.

> If the link shows a "404" page: open
> <https://github.com/Mark852-prog/Roblox-Game-RYDE>, click the branch drop-down
> (it may say `main`), choose `claude/quirky-darwin-t7u0nt`, open the `build`
> folder, click `RYDE.rbxl`, then click the **Download raw file** button (↓ icon).

## Step 3 — Open it in Studio

1. In Roblox Studio click **File → Open from File…**
   (on the start page this may be an **Open** button at the top-left).
2. Choose the `RYDE.rbxl` you just downloaded.
3. The 3D view shows a green field with roads. Use the right mouse button
   to look around and **W A S D** to move the camera.

Now open the three panels you will need:

4. Click the **View** tab at the top.
5. Click **Explorer**, **Properties** and **Output** so each one is highlighted.
   They appear as panels on the sides/bottom of the window.

## Step 4 — Play

1. Click the **Home** tab, then the big **Play** button (or press **F5**).
2. You spawn on a concrete plaza, facing a big blue sign that says **RYDE TEST TRACK**.
3. Walk with **W A S D**, jump with **Space**, look around with the right mouse button.
4. To stop, click the red **Stop** button (or press **Shift + F5**).

### What you should see

- **Top-left corner:** a dark box (the developer HUD) showing:
  - `RYDE dev build 0.1.0`
  - `Server: OK (v0.1.0)` ← this proves the server started correctly
  - `FPS`, your `Speed` in km/h and mph, the `Surface` you're standing on and its `Grip`
  - Press **F2** to hide/show it.
- **Output panel:** these lines (other Roblox messages may be mixed in):
  ```
  [RYDE] Server starting - version 0.1.0 (Milestone 1 - Project setup and test track)
  [RYDE] 4 vehicle configs validated OK
  [RYDE] Server ready - all startup checks passed
  [RYDE] Client starting - version 0.1.0
  ```

There are **no bikes yet** — that's Milestone 2. Milestone 1 is about
confirming the project opens, the scripts run, and the test map is right.

## Step 5 — Report back

Please tell me:

1. Did the place open, and did you spawn on the plaza?
2. Does the HUD say `Server: OK`?
3. Copy any **red** or **orange** text from the Output panel that starts with `[RYDE]`
   (or any red error at all).
4. Optionally, walk to a few areas from the checklist in [TESTING.md](TESTING.md)
   and tell me anything that looks wrong (floating parts, unreadable signs, etc.).

### How to copy errors from Output

Click on a line in the Output panel, press **Ctrl + A** (select all) then
**Ctrl + C** (copy), and paste into your message to me. On a Mac use **Cmd**.

---

## Common problems

| Problem | What to do |
|---|---|
| HUD says `Server: waiting...` forever | A server script failed. Look for red text in Output and send it to me. |
| HUD says `Server: PROBLEMS` | Look for orange `[RYDE]` warnings in Output and send them to me. |
| No HUD at all | Press **F2**. If still nothing, check Output for red errors. |
| You fall through the world | Tell me your last `Pos:` value from the HUD. |
| Studio asks to "save changes" when closing | Choose **Don't Save**. Each new version of the game comes as a fresh `RYDE.rbxl`, so don't edit this copy — tell me what you want changed instead. |

## Important: don't edit the downloaded file

All scripts and the map are generated from the source files in this
repository. When I make changes, you download a new `RYDE.rbxl`. Any edits
you make inside Studio would be lost, so describe changes to me instead.

Later (around Milestone 8) we'll publish the game to Roblox — saving player
data only works in a published game. I'll walk you through that when we get there.
