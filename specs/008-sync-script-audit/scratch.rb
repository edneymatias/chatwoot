def annotate_churn_only?(path, base_ref)
  diff = `git diff -U0 #{base_ref} -- #{path}`
  return false if diff.empty?

  content = File.exist?(path) ? File.read(path) : ''
  lines = content.lines
  start_idx = lines.index { |l| l.start_with?('# == Schema Information') }
  return false unless start_idx

  end_idx = start_idx
  end_idx += 1 while end_idx < lines.length && lines[end_idx].match?(/^\s*(#|$)/)

  diff.lines.each do |line|
    if match = line.match(/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/)
      new_start = match[1].to_i
      return false unless new_start >= start_idx + 1 && new_start <= end_idx + 1
    elsif line.start_with?('+', '-') && !line.start_with?('+++', '---')
      return false unless line.match?(/^[+-]\s*(#|$)/)
    end
  end

  true
end
