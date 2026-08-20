import os
import re

directories = [
    'app/javascript/dashboard/routes/dashboard/scout/',
    'app/javascript/dashboard/routes/dashboard/settings/scout/',
    'app/javascript/dashboard/components-next/Scout/'
]

for d in directories:
    for root, _, files in os.walk(d):
        for file in files:
            if file.endswith('.vue'):
                filepath = os.path.join(root, file)
                with open(filepath, 'r') as f:
                    content = f.read()

                # Find all <Button ... /> tags
                # A robust regex to find <Button ...> and check if it has a label
                def replacer(match):
                    button_tag = match.group(0)
                    if 'label=' in button_tag:
                        # Remove icon="..."
                        button_tag = re.sub(r'\s*icon="[^"]+"\s*', ' ', button_tag)
                    return button_tag

                # Match <Button followed by any characters until >
                new_content = re.sub(r'<Button[^>]+>', replacer, content)

                if new_content != content:
                    with open(filepath, 'w') as f:
                        f.write(new_content)
                    print(f"Updated {filepath}")
