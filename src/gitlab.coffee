# Description:
#   Post gitlab related events using gitlab hooks
#
# Dependencies:
#   "url" : ""
#   "querystring" : ""
#
# Configuration:
#   GITLAB_URL
#   GITLAB_CHANNEL
#   GITLAB_DEBUG
#   GITLAB_BRANCHES
#   GITLAB_SHOW_COMMITS_LISTG
#   GITLAB_SHOW_MERGE_DESCRIPTION
#
#   Put http://<HUBOT_URL>:<PORT>/gitlab/system as your system hook
#   Put http://<HUBOT_URL>:<PORT>/gitlab/web as your web hook (per repository)
#   You can also append "?targets=%23room1,%23room2" to the URL to control the
#   message destination.  Using the "target" parameter to override the
#   GITLAB_CHANNEL configuration value.
#   You can also append "?branches=master,deve" to the URL to control the
#   message destination.  Using the "target" parameter to override the
#   GITLAB_BRANCHES configuration value.
#
# Commands:
#   None
#
# URLS:
#   /gitlab/system
#   /gitlab/web
#
# Author:
#   omribahumi, spruce

url = require 'url'
querystring = require 'querystring'



module.exports = (robot) ->
  gitlabChannel = process.env.GITLAB_CHANNEL or "#gitlab"
  showCommitsList = process.env.GITLAB_SHOW_COMMITS_LIST or "1"
  showMergeDesc = process.env.GITLAB_SHOW_MERGE_DESCRIPTION or "1"
  debug = process.env.GITLAB_DEBUG?
  branches = ['all']
  if process.env.GITLAB_BRANCHES?
    branches = process.env.GITLAB_BRANCHES.split ','

  if robot.adapter.constructor.name is 'IrcBot'
    bold = (text) ->
      "\x02" + text + "\x02"
    underline = (text) ->
      "\x1f" + text + "\x1f"
  else
    bold = (text) ->
      text
    underline = (text) ->
      text

  trim_commit_url = (url) ->
    url.replace(/(\/[0-9a-f]{9})[0-9a-f]+$/, '$1')

  handler = (type, req, res) ->
    query = querystring.parse(url.parse(req.url).query)
    hook = req.body

    if debug
      console.log('query', query)
      console.log('hook', hook)

    user = {}
    user.room = if query.targets then query.targets else gitlabChannel
    user.type = query.type if query.type
    if query.branches
      branches = query.branches.split ','

    if hook.object_kind == "build"
      robot.send user, "Build of "+hook.project_name+' id: '+hook.project_id+' ref: '+hook.ref+' name: '+hook.build_name+' stage: ' + hook.build_stage + ' status: ' + hook.build_status + '. Time: ' + hook.build_duration

    switch type
      when "system"
        switch hook.event_name
          when "project_create"
            robot.send user, "Yay! New gitlab project #{bold(hook.name)} created by #{bold(hook.owner_name)} (#{bold(hook.owner_email)})"
          when "project_destroy"
            robot.send user, "Oh no! #{bold(hook.owner_name)} (#{bold(hook.owner_email)}) deleted the #{bold(hook.name)} project"
          when "user_add_to_team"
            robot.send user, "#{bold(hook.project_access)} access granted to #{bold(hook.user_name)} (#{bold(hook.user_email)}) on #{bold(hook.project_name)} project"
          when "user_remove_from_team"
            robot.send user, "#{bold(hook.project_access)} access revoked from #{bold(hook.user_name)} (#{bold(hook.user_email)}) on #{bold(hook.project_name)} project"
          when "user_create"
            robot.send user, "Please welcome #{bold(hook.name)} (#{bold(hook.email)}) to Gitlab!"
          when "user_destroy"
            robot.send user, "We will be missing #{bold(hook.name)} (#{bold(hook.email)}) on Gitlab"
      when "web"
        message = ""
        # is it code being pushed?
        if hook.ref
          # should look for a tag push where the ref starts with refs/tags
          if /^refs\/tags/.test hook.ref
            tag = hook.ref.split("/")[2..].join("/")
            #this is actually a tag being pushed
            if /^0+$/.test hook.before
              message = "#{bold(hook.user_name)} pushed a new tag (#{bold(tag)}) to #{bold(hook.repository.name)} (#{underline(hook.repository.homepage)})"
            else if /^0+$/.test hook.after
              message = "#{bold(hook.user_name)} removed a tag (#{bold(tag)}) from #{bold(hook.repository.name)} (#{underline(hook.repository.homepage)})"
            else
              if hook.total_commits_count == 1
                message = "#{bold(hook.user_name)} pushed #{bold(hook.total_commits_count)} commit to tag (#{bold(tag)}) in #{bold(hook.repository.name)} (#{underline(hook.repository.homepage)})"
              else
                message = "#{bold(hook.user_name)} pushed #{bold(hook.total_commits_count)} commits to tag (#{bold(tag)}) in #{bold(hook.repository.name)} (#{underline(hook.repository.homepage)})"
          else
            branch = hook.ref.split("/")[2..].join("/")
            # if the ref before the commit is 00000, this is a new branch
            if branch in branches or 'all' in branches
              if /^0+$/.test(hook.before)
                message = "#{bold(hook.user_name)} pushed a new branch (#{bold(branch)}) to #{bold(hook.repository.name)} (#{underline(hook.repository.homepage)})"
              else if /^0+$/.test(hook.after)
                message = "#{bold(hook.user_name)} deleted a branch (#{bold(branch)}) from #{bold(hook.repository.name)} (#{underline(hook.repository.homepage)})"
              else
                message = "#{bold(hook.user_name)} pushed #{bold(hook.total_commits_count)} commits to #{bold(branch)} in #{bold(hook.repository.name)} (#{underline(hook.repository.homepage + '/compare/' + hook.before.substr(0,9) + '...' + hook.after.substr(0,9))})"
                if showCommitsList == "1"
                  merger = []
                  for i in [0...hook.commits.length]
                    merger[i] = "> " + hook.commits[i].id.slice(0,7) + ": " + hook.commits[i].message.replace /\n.*$/gm, ''
                    robot.emit "gitlab-commit", {
                        user: user,
                        repo: hook.repository.name,
                        message: hook.commits[i].message,
                        commit: hook.commits[i]
                      }

                  message += "\r\n" + merger.join "\r\n"
          robot.send user, message
        # not code? must be a something good!
        else
          switch hook.object_kind
            when "wiki_page"
              text = "#{hook.user.name} did #{hook.object_attributes.action} wiki page: #{bold(hook.object_attributes.title)} at #{hook.object_attributes.url}"
              robot.send user, text
            when "issue"
              unless hook.object_attributes.action == "update"
              # for now we don't trigger on update because on manual close it triggers close and update
                text = "Issue #{bold(hook.object_attributes.iid)}: #{hook.object_attributes.title} (#{hook.object_attributes.action}) at #{hook.object_attributes.url}"
                if hook.object_attributes.description
                  # split describtion on \r\n so that It can add >> to every line
                  splitted = hook.object_attributes.description.split  "\r\n"
                  for i in [0...splitted.length]
                    splitted[i] = ">> " + splitted[i]
                  text += "\r\n" + splitted.join "\r\n"
                robot.send user, text
            when "merge_request"
              unless hook.object_attributes.action == "update"
                if showMergeDesc == "1" and hook.object_attributes.description
                  text = "Merge Request ##{bold(hook.object_attributes.iid)}: #{hook.user.username} #{hook.object_attributes.action}  #{hook.object_attributes.title} between #{bold(hook.object_attributes.source_branch)} and #{bold(hook.object_attributes.target_branch)} at #{bold(hook.object_attributes.url)}\n"
                  splitted = hook.object_attributes.description.split  "\r\n"
                  for i in [0...splitted.length]
                    splitted[i] = "> " + splitted[i]
                  text += "\r\n" + splitted.join "\r\n"
                  robot.send user, text
                else
                  robot.send user, "Merge Request ##{bold(hook.object_attributes.iid)}: #{hook.user.username} #{hook.object_attributes.action}  #{hook.object_attributes.title} (#{hook.object_attributes.state}) between #{bold(hook.object_attributes.source_branch)} and #{bold(hook.object_attributes.target_branch)} at #{bold(hook.object_attributes.url)}"

  robot.router.post "/gitlab/system", (req, res) ->
    handler "system", req, res
    res.end "OK"

  robot.router.post "/gitlab/web", (req, res) ->
    handler "web", req, res
    res.end "OK"

  robot.respond /rebuild ?([0-9]+) ?([\w.\-]+)/i, (res) ->
    project_id = res.match[1].trim()
    ref = res.match[2].trim()

    data = JSON.stringify({
        token: process.env.GITLAB_TRIGGER_TOKEN
        ref: ref

    })
    robot.http(GITLAB_URL+"/api/v3/projects/"+project_id+"/trigger/builds")
        .header('Content-Type', 'application/json')
        .post(data) (err, res, body) ->
          # your code here
