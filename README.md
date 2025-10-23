# Dupes Plugin for Yazi

Duplicate files plugin for [Yazi](https://github.com/sxyazi/yazi) file manager, leveraging [jdupes](https://codeberg.org/jbruchon/jdupes) for fast and efficient duplicate detection.

> [!NOTE]
> The latest release of Yazi is required at the moment.

https://github.com/user-attachments/assets/1d87bb52-d326-4720-834c-baac74008d7d

## Features

- 🔍 **Fast Duplicate Detection** - Uses jdupes for high-performance scanning
- 👁️ **Visual Preview** - See duplicates directly in Yazi with deletion markers
- 🧪 **Dry Run Mode** - Preview what will be deleted before applying changes
- ⚙️ **Profile System** - Define custom scanning or override profiles for different use cases
- 💾 **Export Results** - Save scan results to JSON or text files
- 🔒 **Safe by Default** - Confirmation required for destructive operations

## Requirements

- [Yazi](https://github.com/sxyazi/yazi) file manager (v25.5.31+)
- [jdupes](https://codeberg.org/jbruchon/jdupes) command-line tool

## Installation

**Using yazi package manager:**
```sh
ya pkg add mshnwq/dupes
```

**Using nix home-manager (nixpkgs): (recommended)**
```nix
{ pkgs, ... }: {
  programs.yazi = {
    enable = true;
    plugins = {
      # jdupes is self contained within
      dupes = pkgs.yaziPlugins.dupes
    };
  };
}
```

**Using nix home-manager (github):**
```nix
{ pkgs, ... }: {
  home.packages = with pkgs; [ jdupes ];
  programs.yazi = {
    enable = true;
    plugins = {
      dupes = pkgs.fetchFromGitHub {
        owner = "mshnwq";
        repo = "dupes.yazi";
        rev = "4666b6f299c2257c011f622319ae97fab8adbabe";
        hash = "sha256-v9xuSY/i/trIHHbOPbijd0AmcUb2vufNL9BSjBE6+Vo=";
      };
    };
  };
}
```

**Manual installation:**
```sh
git clone https://github.com/mshnwq/dupes.yazi.git ~/.config/yazi/plugins/dupes.yazi
```

## Usage

Configuration in `~/.config/yazi/init.lua`:
```lua
require("dupes"):setup {
	-- Global settings
	save_op = false,        -- Save results to file by default
	-- auto_confirm = true, -- Skip confirmation for apply (use with caution!)
	
	profiles = {
		-- Interactive mode: recursively scan and display duplicates
		interactive = {
			args = { "-r" },
		},
		-- Apply mode: recursively scan and DELETE duplicates
		apply = {
			args = { "-r", "-N", "-d" },
			save_op = true,  -- Save results before deletion
		},
		-- Custom profile example (uncomment to use)
		-- custom = {
		-- 	args = { "-r", "-s", },  -- Your custom jdupes flags
		-- },
	},
}
```

Keybindings in `~/.config/yazi/keymap.toml`:
```toml
[[manager.prepend_keymap]]
on = ["<A-J>", "i"]
run = "plugin dupes interactive"
desc = "Run dupes interactive"

[[manager.prepend_keymap]]
on = ["<A-J>", "o"]
run = "plugin dupes override"
desc = "Run dupes override"

[[manager.prepend_keymap]]
on = ["<A-J>", "d"]
run = "plugin dupes dry"
desc = "Run dupes dry"

[[manager.prepend_keymap]]
on = ["<A-J>", "a"]
run = "plugin dupes apply"
desc = "Run dupes apply"

# [[mgr.prepend_keymap]]
# on = ["<A-J>", "c"]
# run = "plugin dupes custom"
# desc = "Run dupes custom"
```

### Profiles

#### 🔍 Interactive Mode
Scans for duplicates and displays them in Yazi. Safe to use - no files are deleted.

```lua
interactive = {
	args = { "-r" },  -- Recursive scan
}
```
#### 🧪 Dry Run Mode (inherits apply mode)
Shows what **would** be deleted using the same settings as apply mode. Files marked 'X' will be deleted. The first file in each duplicate set is kept.

- Normal files: displayed normally (will be kept)
- Files marked 'X': will be deleted

#### ⚠️ Apply Mode
**DESTRUCTIVE OPERATION** - Permanently deletes duplicate files.

```lua
apply = {
	args = { "-r", "-N", "-d" },
	save_op = true,  -- Saves results to dupes.json
}
```

#### 🛠️ Override Mode
Opens an input dialog where you can enter custom jdupes arguments for one-time scans.

**Example inputs:**
- `-r -s` - Recursive, follow symlinks

## Configuration Options

### Global Settings

```lua
require("dupes"):setup {
	save_op = false,        -- Default: don't save results to file
	auto_confirm = false,   -- Default: prompt before deletion
	profiles = {
		-- Your profiles here
	},
}
```

### Profile Settings

Each profile can have:

```lua
profile_name = {
	args = { "-r", "-N" },  -- jdupes command arguments
	save_op = true,         -- Override global save_op for this profile
}
```

### Common jdupes Flags

| Flag | Description |
|------|-------------|
| `-r` | Recursive search in subdirectories |
| `-d` | **DELETE duplicates (DESTRUCTIVE!)** |
| `-j` | JSON output (added by plugin) |
| `-s` | Follows symbolic links |

See `jdupes --help` for complete flag list.

## Custom Examples

### Example:  Find duplicates in current directory only
```lua
shallow = {
	args = {},  -- No -r flag, current directory only
}
```

## Output Files

When `save_op = true`, results are saved to:

- **dupes.json** - JSON format
- **dupes.txt**  - Text format (when destructive)

Files are saved in the current working directory.

## License

This plugin is MIT-licensed. For more information check the [LICENSE](LICENSE) file.

## Credits

- [Yazi](https://github.com/sxyazi/yazi) file manager
- [jdupes](https://codeberg.org/jbruchon/jdupes) for duplicate detection
- [boydaihungst](https://github.com/boydaihungst) for help on Yazi's [Discord](https://discord.gg/qfADduSdJu) channel

## See Also

- [jdupes Documentation](https://codeberg.org/jbruchon/jdupes)
- [Yazi Plugins](https://yazi-rs.github.io/docs/plugins/overview)
