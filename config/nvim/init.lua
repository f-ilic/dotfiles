-- Neovim configuration matching Helix key bindings
-- Navigation: i=up, j=left, k=down, l=right
-- Home/End: u=start, o=end
-- Deletion: h=backspace, ;=delete

-- Basic settings
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true
vim.opt.wrap = false
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 50

-- Leader key
vim.g.mapleader = " "

-- NORMAL MODE NAVIGATION
-- Core ijkl movement
vim.keymap.set('n', 'i', 'k', { desc = 'Move up' })
vim.keymap.set('n', 'j', 'h', { desc = 'Move left' })
vim.keymap.set('n', 'k', 'j', { desc = 'Move down' })
vim.keymap.set('n', 'l', 'l', { desc = 'Move right' })

-- Home/End keys
vim.keymap.set('n', 'u', '^', { desc = 'Go to line start' })
vim.keymap.set('n', 'o', '$', { desc = 'Go to line end' })

-- Deletion keys
vim.keymap.set('n', 'h', 'X', { desc = 'Delete char backward' })
vim.keymap.set('n', ';', 'x', { desc = 'Delete char forward' })

-- Ctrl+a and Ctrl+e for line start/end (like in your config)
vim.keymap.set('n', '<C-a>', '^', { desc = 'Go to line start' })
vim.keymap.set('n', '<C-e>', '$', { desc = 'Go to line end' })

-- VISUAL MODE (similar to Helix select mode)
-- Core ijkl movement in visual mode
vim.keymap.set('v', 'i', 'k', { desc = 'Extend up' })
vim.keymap.set('v', 'j', 'h', { desc = 'Extend left' })
vim.keymap.set('v', 'k', 'j', { desc = 'Extend down' })
vim.keymap.set('v', 'l', 'l', { desc = 'Extend right' })

-- Home/End in visual mode
vim.keymap.set('v', 'u', '^', { desc = 'Extend to line start' })
vim.keymap.set('v', 'o', '$', { desc = 'Extend to line end' })

-- Deletion in visual mode
vim.keymap.set('v', 'h', 'X', { desc = 'Delete backward' })
vim.keymap.set('v', ';', 'x', { desc = 'Delete forward' })

-- Ctrl+a and Ctrl+e in visual mode
vim.keymap.set('v', '<C-a>', '^', { desc = 'Extend to line start' })
vim.keymap.set('v', '<C-e>', '$', { desc = 'Extend to line end' })

-- INSERT MODE
-- Ctrl+a and Ctrl+e for line start/end in insert mode
vim.keymap.set('i', '<C-a>', '<C-o>^', { desc = 'Go to line start' })
vim.keymap.set('i', '<C-e>', '<C-o>$', { desc = 'Go to line end' })

-- RESTORE LOST FUNCTIONALITY (like in your Helix config)
-- Since we remapped some keys, we need alternatives for the original functions

-- Restore insert mode (original 'i' was enter insert mode)
vim.keymap.set('n', 'a', 'a', { desc = 'Append after cursor' })
vim.keymap.set('n', 'A', 'I', { desc = 'Insert at line start' })

-- Restore join lines (original 'j' was join)
vim.keymap.set('n', 'J', 'J', { desc = 'Join lines' })

-- Restore search functionality
vim.keymap.set('n', '/', '/', { desc = 'Search forward' })
vim.keymap.set('n', '?', '?', { desc = 'Search backward' })
vim.keymap.set('n', 'n', 'n', { desc = 'Next search result' })
vim.keymap.set('n', 'N', 'N', { desc = 'Previous search result' })

-- Restore undo/redo (in case 'u' conflicts)
vim.keymap.set('n', 'z', 'u', { desc = 'Undo' })
vim.keymap.set('n', 'Z', '<C-r>', { desc = 'Redo' })

-- Visual selection
vim.keymap.set('n', 's', 'v', { desc = 'Enter visual mode' })
vim.keymap.set('n', 'S', 'V', { desc = 'Enter visual line mode' })

-- Delete selection and other visual mode operations
vim.keymap.set('v', 'x', 'd', { desc = 'Delete selection' })
vim.keymap.set('v', 'y', 'y', { desc = 'Yank selection' })
vim.keymap.set('v', 'c', 'c', { desc = 'Change selection' })
vim.keymap.set('v', 'd', 'd', { desc = 'Delete selection' })
vim.keymap.set('v', 'p', 'p', { desc = 'Paste over selection' })

-- ADDITIONAL USEFUL MAPPINGS
-- Window navigation (useful for splits)
vim.keymap.set('n', '<leader>w', '<C-w>', { desc = 'Window commands' })

-- File operations
vim.keymap.set('n', '<leader>fs', ':w<CR>', { desc = 'Save file' })
vim.keymap.set('n', '<leader>fq', ':q<CR>', { desc = 'Quit' })
vim.keymap.set('n', '<leader>fx', ':x<CR>', { desc = 'Save and quit' })

-- Clear search highlight
vim.keymap.set('n', '<leader>h', ':nohlsearch<CR>', { desc = 'Clear search highlight' })

-- Buffer navigation
vim.keymap.set('n', '<leader>bn', ':bnext<CR>', { desc = 'Next buffer' })
vim.keymap.set('n', '<leader>bp', ':bprevious<CR>', { desc = 'Previous buffer' })
vim.keymap.set('n', '<leader>bd', ':bdelete<CR>', { desc = 'Delete buffer' })

-- Tab navigation
vim.keymap.set('n', '<leader>tn', ':tabnext<CR>', { desc = 'Next tab' })
vim.keymap.set('n', '<leader>tp', ':tabprevious<CR>', { desc = 'Previous tab' })
vim.keymap.set('n', '<leader>tc', ':tabclose<CR>', { desc = 'Close tab' })

-- File explorer (if you want basic file browsing)
vim.keymap.set('n', '<leader>e', ':Explore<CR>', { desc = 'File explorer' })

-- Yank to system clipboard
vim.keymap.set('v', '<leader>y', '"+y', { desc = 'Yank to system clipboard' })
vim.keymap.set('n', '<leader>Y', '"+yy', { desc = 'Yank line to system clipboard' })

-- Paste from system clipboard
vim.keymap.set('n', '<leader>p', '"+p', { desc = 'Paste from system clipboard' })
vim.keymap.set('v', '<leader>p', '"+p', { desc = 'Paste from system clipboard' })
