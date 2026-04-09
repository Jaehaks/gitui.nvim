# gitui.nvim

[gitui](https://github.com/extrawurst/gitui) integration for Neovim.

https://github.com/user-attachments/assets/cf284842-0c01-4b24-a8fa-524f17723ae5

---

## Why?

I used `neogit` and its workflow is very great. I haven't seen a tool that surpasses this for git workflow.
It has very convenient shortcut system and show editor with diff view, very affluent features.
The biggest drawback of it is execution speed in Windows. I went around looking for faster workflow.
The tools which use `libgit2` has advantages for performance speed. Among of them, `gitui` meets what I want.

Other gitui integration plugins just show the tool in terminal. It cannot open files or commit message in neovim.
And `gitui` has some bugs (in Windows only?) that it crashed when I commit after opening some files using external editor.
It has a few feature to write commit message.
So this plugin's workflow is helpful because `gitui.nvim` terminates gitui process after opening file in neovim instance
and open commit message with diff view.

---

## ✨ Features

- **Run gitui in a Neovim terminal tab** — gitui opens in a new tab inside your current Neovim session.
- **Open files from `edit_file`** — Open file in your existing neovim instance.
- **Open commit message with Diff View from `commit`** —  Diff view automatically opens alongside commit message.
- **Live Diff View updates** — The diff view with commit message refreshes automatically when git status is changed.
- **Jump to file from Diff View** — Press `<CR>` on a hunk line in Diff view to jump to the exact location in the source file.
- **Custom theme support** — Use the bundled `theme.ron` or specify your own gitui theme path.
- **Cross-platform** — Works on Windows, Linux, and macOS.

---

## 📋 Requirements

- **Neovim** >= 0.11
- **[gitui](https://github.com/extrawurst/gitui)** — Must be installed and available in your `$PATH`.

---

## 📦 Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "Jaehaks/gitui.nvim",
  keys = {
    { "<leader>g", function() require("gitui").open() end, desc = "Open Gitui" },
  },
  opts = {},               -- Uses defaults; see Configuration below
}
```

---

## ⚙️ Default Configuration

<details>
<summary>Click to expand default configuration</summary>

```lua
require("gitui").setup({
  -- Path to a custom gitui theme file (theme.ron).
  -- When set to nil, the bundled theme (data/theme.ron) is used.
  ---@type string?
  theme_path = nil,

  -- Delay in [ms] before switching to insert mode automatically after the terminal opens.
  -- Set to nil to disable automatic insert mode.
  ---@type integer?
  delay_startinsert = 50,
})
```

</details>

---

## 🚀 Usage / Workflow

> `gitui.nvim` doesn't contaminate keymaps in gitui. If you enter to terminal mode, gitui shortcuts will be used

---

### 1. Open a file with `edit_file` (Open in Editor)

While in gitui, select a file in `Status` tab and press shortcut(default `e` in gitui) to open the file in current neovim.
The next step is written below.

1. The selected file opens in your **current Neovim instance** (not a new Neovim process).
2. The gitui terminal buffer closes automatically.
3. The opened file is loaded in tab where you called gitui open() function.

---

### 3. Commit with `Ctrl-e` — Commit Message + Diff View

When gitui opens an external editor for a commit message (default `<C-e>` in gitui).
You can write commit message in neovim and If you write and close the commit message buffer,
the contents are saved in commit message box in gitui. The next step is written below.

1. Open commit message in gitui
2. Put `<C-e>` to open the commit message in current neovim
1. A **new tab** opens with the commit message buffer.
2. A **Diff View** window automatically opens in a split above it.
3. The Diff View displays all changes grouped by **Staged**, **Unstaged**, and **Untracked** files.

#### **Diff View Keymaps**

| Key     | Action                                                                                       |
| ------- | -------------------------------------------------------------------------------------------- |
| `<Tab>` | Toggle fold (group / file / hunk level)                                                      |
| `<CR>`  | Jump to the corresponding file and line (opens in a vsplit besides of commit message window) |

#### **Diff View Auto-Refresh**

You can open auxiliary buffer from `<CR>` in diff view window to modify residue works.
In auxiliary buffer,

- When some codes are modified, the changes will be updated in diff view after you save the buffer.
- When you change git state(staging/unstaging) of hunk using git integration plugins like `gitsigns.nvim`, the diff view will be updated.

#### **After Committing**

When you save and quit the commit message (`:wq`) or close the diff view:
- Focus automatically returns to the **gitui tab**.
- The messages will be inserted in commit message box in gitui.
- Then you complete the commit with `<C-c>`(default in gitui)

---

### 4. Quit gitui

Press `q` inside the gitui terminal:
- The gitui process exits and the terminal buffer is wiped out.
- You are returned to your previous tab.
- I don't like terminal buffer is remained behind buffer list and opening gitui terminal is very fast.

---

## 🎨 Highlight Groups

The plugin defines the following highlight groups. You can override them with `vim.api.nvim_set_hl()` **after** calling `setup()`.

| Highlight Group     | Default                            | Used For                                                 |
| ------------------- | ---------------------------------- | -------------------------------------------------------- |
| `GituiGroupTitle`   | `fg=#0d1117` `bg=#00ff87` **bold** | Group headers in diff view (Staged, Unstaged, Untracked) |
| `GituiFileAdded`    | `fg=#ffdd00` *italic*              | Newly added file titles in diff view                     |
| `GituiFileModified` | `fg=#ff2f55` *italic*              | Modified file titles in diff view                        |
| `GituiFileDeleted`  | `fg=#8b8b8b` *italic*              | Deleted file titles in diff view                         |
| `GituiFileRenamed`  | `fg=#00aaff` *italic*              | Renamed file titles in diff view                         |
| `GituiFoldIcon`     | links to `Comment`                 | Color of fold indicators (`>` / `v`)                     |

---

## 📄 License

[MIT](./LICENSE)

## Acknowledgements

- [neogit](https://github.com/neogitorg/neogit)

