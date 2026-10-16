# imports/

Third-party Creator Store models saved from Roblox Studio, waiting to be
checked and adapted. **Nothing in this folder is part of the game** until it
has been inspected and converted (scripts removed, branding removed,
restructured for our bike system).

Check a file:

    lune run tools/inspect-import imports

## How to add a model (beginner steps)

1. Open the asset's page on create.roblox.com and click **Get Model**
   (it is added to your Roblox inventory).
2. In Roblox Studio: **File → New → Baseplate** (an empty place - do NOT use
   the RYDE place, and do NOT press Play: some of these models contain scripts).
3. **View → Toolbox → Inventory → My Models**, click the model to insert it.
   If Studio warns that it contains scripts, insert it anyway - scripts don't
   run while you're only editing.
4. In the **Explorer**, right-click the model → **Save to File...** →
   save as `<short name>.rbxm` (e.g. `surron_truly.rbxm`).
5. On github.com, open this repository, switch to the branch
   `claude/quirky-darwin-t7u0nt`, open the `imports` folder,
   **Add file → Upload files**, drag the `.rbxm` files in, **Commit changes**.
