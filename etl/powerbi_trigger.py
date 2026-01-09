"""Trigger a Power BI dataset refresh using service principal credentials.
Set the following env vars in your .env file:
- PBI_TENANT_ID
- PBI_CLIENT_ID
- PBI_CLIENT_SECRET
- PBI_WORKSPACE_ID
- PBI_DATASET_ID
"""
import os
import requests

TENANT = os.getenv('PBI_TENANT_ID')
CLIENT = os.getenv('PBI_CLIENT_ID')
SECRET = os.getenv('PBI_CLIENT_SECRET')
WORKSPACE = os.getenv('PBI_WORKSPACE_ID')
DATASET = os.getenv('PBI_DATASET_ID')

if not all([TENANT, CLIENT, SECRET, WORKSPACE, DATASET]):
    print('Power BI credentials not fully configured in env; skipping trigger')
    exit(0)

# Get access token
token_url = f'https://login.microsoftonline.com/{TENANT}/oauth2/v2.0/token'
data = {
    'grant_type': 'client_credentials',
    'client_id': CLIENT,
    'client_secret': SECRET,
    'scope': 'https://analysis.windows.net/powerbi/api/.default'
}
resp = requests.post(token_url, data=data)
resp.raise_for_status()
access_token = resp.json()['access_token']

# Trigger refresh
api_url = f'https://api.powerbi.com/v1.0/myorg/groups/{WORKSPACE}/datasets/{DATASET}/refreshes'
headers = {'Authorization': f'Bearer {access_token}', 'Content-Type': 'application/json'}
body = {"notifyOption": "NoNotification"}
res = requests.post(api_url, headers=headers, json=body)
if res.status_code in (200,201):
    print('Refresh triggered successfully')
else:
    print('Failed to trigger refresh:', res.status_code, res.text)
    res.raise_for_status()
