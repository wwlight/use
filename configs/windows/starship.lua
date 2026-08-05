load(io.popen('starship init cmd'):read("*a"))()
-- Read the HOME environment variable.
local home = os.getenv("HOME")
-- Build the path.
local starship_config = home.."\\.config\\starship\\starship.toml"
-- Set the environment variable.
os.setenv("STARSHIP_CONFIG", starship_config)
