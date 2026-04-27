# signal.nvim

Signal messenger inside Neovim, powered by [signal-cli](https://github.com/AsamK/signal-cli).

## Features

- Conversation list with last message preview and unread badges
- Thread view with full message history
- Compose and send messages
- Background polling with toast notifications for new messages
- Group chat support

## Setup

### 1. Install Java 17+

```bash
sudo apt install default-jre
```

### 2. Install signal-cli

Download the latest release from https://github.com/AsamK/signal-cli/releases

```bash
# Example for v0.13.x
wget https://github.com/AsamK/signal-cli/releases/download/v0.13.10/signal-cli-0.13.10.tar.gz
tar -xzf signal-cli-0.13.10.tar.gz
sudo mv signal-cli-0.13.10 /opt/signal-cli
sudo ln -sf /opt/signal-cli/bin/signal-cli /usr/local/bin/signal-cli
```

### 3. Register your phone number

```bash
signal-cli -u +YOURNUMBER register
signal-cli -u +YOURNUMBER verify CODE
```

### 4. Test

```bash
signal-cli -u +YOURNUMBER listContacts
```

### 5. Add to Neovim

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  dir = "~/signal.nvim",
  config = function()
    require("signal").setup({ phone_number = "+YOURNUMBER" })
  end,
}
```

Add a keymap:

```lua
vim.keymap.set("n", "<leader>si", function() require("signal").toggle() end,
  { desc = "Toggle Signal" })
```

## Keymaps

### Conversation list

| Key | Action |
|-----|--------|
| `<CR>` | Open thread |
| `r` | Refresh |
| `q` / `<Esc>` | Close |

### Thread view

| Key | Action |
|-----|--------|
| `s` | Compose and send a message |
| `r` | Refresh messages |
| `q` / `<Esc>` | Back to conversation list |

### Compose popup

| Key | Action |
|-----|--------|
| `<C-s>` | Send |
| `q` / `<Esc>` | Cancel |

## Health check

```
:checkhealth signal
```

## Config options

```lua
require("signal").setup({
  phone_number  = "+43...",   -- required
  poll_interval = 30,         -- seconds between background polls
  notif_ttl     = 5,          -- toast auto-dismiss seconds
  window_width  = 0.9,        -- floating window width fraction
  signal_cmd    = "signal-cli", -- path to signal-cli binary
})
```
