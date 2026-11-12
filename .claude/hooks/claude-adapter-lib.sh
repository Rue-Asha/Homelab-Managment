#!/usr/bin/env bash
# Claude adapter library (docs/contracts.md C2). Source it.

# claude_to_neutral: stdin Claude hook JSON -> stdout neutral JSON
#   {"event":"pre_tool"|"prompt"|"notification","tool":s,"input":{...},"cwd":s}
# The event comes from hook_event_name, else from the payload's shape (tool_name, prompt, message).
# On invalid JSON jq's own error goes to stderr and the status is non-zero; the adapters rely on that
# text to stay identical to the old hooks.
# key (default command) is the tool_input field the old hook read first: a tool_input that is neither
# an object nor null fails on it with the old hook's jq error and status. An empty key reads it as {}.
# A tool name outside the map whose lowercase is a neutral name becomes other:<name>, so it never
# passes for the mapped tool (the old hooks matched the exact names).
# Usage: claude_to_neutral [key] < claude.json
claude_to_neutral() {
	jq -c --arg cwd "$PWD" --arg key "${1-command}" '
	{Bash: "shell", Read: "read", Write: "write", Edit: "edit", NotebookEdit: "notebook_edit",
	 Grep: "search", Glob: "glob"} as $names
	| (if $key != "" and (.tool_input | type | IN("object", "null") | not) then .tool_input[$key] else null end) as $_
	| ((.tool_input | objects) // {}) as $ti
	| (if has("prompt") then {prompt: .prompt} else {} end) as $p
	| (if has("message") then {message: .message} else {} end) as $m
	| {event: ((.hook_event_name // "") as $h
	     | if $h == "PreToolUse" then "pre_tool"
	       elif $h == "UserPromptSubmit" then "prompt"
	       elif $h == "Notification" then "notification"
	       elif has("tool_name") then "pre_tool"
	       elif has("prompt") then "prompt"
	       elif has("message") then "notification"
	       else "pre_tool" end),
	   tool: (.tool_name | if type == "string"
	     then ($names[.] // (ascii_downcase | if IN($names[]) then "other:" + . else . end)) else "" end),
	   input: ($ti
	     | (if has("file_path") or has("notebook_path")
	        then .path = (.file_path // .notebook_path) | del(.file_path, .notebook_path) else . end)
	     | . + $p + $m),
	   cwd: $cwd}'
}

# render_claude <style> <event>: stdin neutral decision JSON -> Claude protocol
#   style: exit2 (deny = exit 2 + stderr lines) | json (hookSpecificOutput on stdout)
#   event: pre_tool | prompt
#   allow prints nothing and returns 0; exit2 deny prints the reason to stderr and returns 2;
#   json: deny/ask -> permissionDecision JSON, context -> additionalContext JSON (pretty-printed,
#   as the old hooks' `jq -n` did).
# Usage: render_claude json pre_tool < decision.json
render_claude() {
	local style=$1 event=$2 decision hook
	case $event in
	prompt) hook=UserPromptSubmit ;;
	*) hook=PreToolUse ;;
	esac
	decision=$(cat)
	case $(jq -r '.decision // "allow"' <<<"$decision") in
	deny)
		if [[ $style == exit2 ]]; then
			printf '%s\n' "$(jq -r '.reason // ""' <<<"$decision")" >&2
			return 2
		fi
		jq --arg h "$hook" '{hookSpecificOutput: {hookEventName: $h, permissionDecision: "deny", permissionDecisionReason: .reason}}' <<<"$decision"
		;;
	ask)
		jq --arg h "$hook" '{hookSpecificOutput: {hookEventName: $h, permissionDecision: "ask", permissionDecisionReason: .reason}}' <<<"$decision"
		;;
	context)
		jq --arg h "$hook" '{hookSpecificOutput: {hookEventName: $h, additionalContext: .context}}' <<<"$decision"
		;;
	esac
	return 0
}
