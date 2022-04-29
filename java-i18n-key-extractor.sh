#!/bin/bash

sbtFile="build.sbt"
projectPath="./src/main/java/"
messagesPath="./src/main/resources/"
ruMessagesFile="messages.ru"
enMessagesFile="messages.en"

if test -f "$sbtFile";
then
  projectPath="./app/"
  messagesPath="./conf/"
fi

if [[ ! -e ${messagesPath} ]]; then
    mkdir ${messagesPath}
fi

touch ${messagesPath}${ruMessagesFile}
touch ${messagesPath}${enMessagesFile}

keys=($(grep -h -r "I18nMessage.of(" ${projectPath} | awk '{split($0,a,"\""); print a[2]"="}'))
for key in "${keys[@]}"
do
  if ! grep -Fq "${key}" ${messagesPath}${ruMessagesFile}
  then
    echo "${key}" >> ${messagesPath}${ruMessagesFile}
  fi

  if ! grep -Fq "${key}" ${messagesPath}${enMessagesFile}
  then
    echo "${key}" >> ${messagesPath}${enMessagesFile}
  fi
done
