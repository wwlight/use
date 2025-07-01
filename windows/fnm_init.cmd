:: 使用说明：在 cmd 路径后追加 /k %USERPROFILE%\fnm_init.cmd

@echo off
if not defined FNM_AUTORUN_GUARD (
    set "FNM_AUTORUN_GUARD=AutorunGuard"
    FOR /f "tokens=*" %%z IN ('fnm env --use-on-cd') DO CALL %%z
)
