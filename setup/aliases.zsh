# aliases for stuff in BernardScripts
# gets symlinked into $ZSH_CUSTOM by setupZshAliases.sh, oh-my-zsh sources it on startup

scripts=${0:A:h:h}   # repo root, works through the symlink

alias sqlconnenv="sh $scripts/MysqlConnEnv/mysqlconnenv.sh"
alias launchproject="sh $scripts/launchProject/launchproject.sh"
alias deployproject="bash $scripts/QuickDeploy/deployproject.sh"

unset scripts
