# Sample Data — Documents Folder
#
# Place your PDF files in this folder before running the scripts.
#
# The upload script (01_upload_to_search.py) will:
#   1. Read each PDF file from this folder
#   2. Extract text page by page
#   3. Chunk the text into ~1000-character pieces
#   4. Generate embeddings using Azure OpenAI
#   5. Upload them to Azure AI Search
#   6. Create a Foundry IQ Knowledge Base on top
#
# If you don't have your own PDFs, run:
#   python scripts/00_generate_sample_docs.py
# to generate sample IOC health-check policy documents for testing.
