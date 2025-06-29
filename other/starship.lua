load(io.popen('starship init cmd'):read("*a"))()
-- 获取 HOME 环境变量
local home = os.getenv("HOME")
-- 构造路径
local starship_config = home.."\\.config\\starship\\starship.toml"
-- 设置环境变量
os.setenv("STARSHIP_CONFIG", starship_config)
