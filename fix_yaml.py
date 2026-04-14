file_path = ".github/workflows/gemini-review.yml"
with open(file_path, "r") as f:
    content = f.read()

import re
content = content.replace("gcp_project_id: '${{ vars.GOOGLE_CLOUD_PROJECT }}'", "gcp_project_id: 'vorce-studios'")

with open(file_path, "w") as f:
    f.write(content)
