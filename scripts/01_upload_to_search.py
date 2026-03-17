"""
01_upload_to_search.py — Upload PDF files to Azure AI Search + Create Foundry IQ Knowledge Base

Adapted from the accelerator repo's 06_upload_to_search.py.
Simplified: NO SQL, NO Fabric — just PDFs → AI Search → Knowledge Base.

What this script does:
  1. Creates a search index with vector search + semantic configuration
  2. Reads each PDF from data/documents/
  3. Extracts text page by page, then chunks by sentences (~1000 chars each)
  4. Generates embeddings using your Azure OpenAI embedding model
  5. Uploads all chunks to the search index
  6. Creates a Foundry IQ Knowledge Source + Knowledge Base on top of the index

Prerequisites:
  - 'azd up' completed (or set AZURE_AI_SEARCH_ENDPOINT + AZURE_OPENAI_ENDPOINT in .env)
  - PDF files placed in data/documents/
  - Embedding model deployed (text-embedding-3-small by default)

Usage:
    python 01_upload_to_search.py
"""

import os
import sys
import json
import re
from pathlib import Path

# Load environment from azd + project .env
from load_env import load_all_env, get_data_folder
load_all_env()

from azure.identity import DefaultAzureCredential
from openai import AzureOpenAI
from azure.search.documents import SearchClient
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents.indexes.models import (
    SearchIndex,
    SearchField,
    SearchFieldDataType,
    VectorSearch,
    HnswAlgorithmConfiguration,
    VectorSearchProfile,
    AzureOpenAIVectorizer,
    AzureOpenAIVectorizerParameters,
    SemanticConfiguration,
    SemanticField,
    SemanticPrioritizedFields,
    SemanticSearch,
    # Foundry IQ — Knowledge Base models (preview)
    KnowledgeBase,
    KnowledgeBaseAzureOpenAIModel,
    KnowledgeSourceReference,
    KnowledgeRetrievalOutputMode,
    KnowledgeRetrievalLowReasoningEffort,
    SearchIndexKnowledgeSource,
    SearchIndexKnowledgeSourceParameters,
    SearchIndexFieldReference,
)
from pypdf import PdfReader

# ============================================================================
# Configuration
# ============================================================================

# Azure endpoints — loaded from azd environment or .env
AZURE_AI_ENDPOINT = (
    os.getenv("AZURE_AI_ENDPOINT")
    or os.getenv("AZURE_OPENAI_ENDPOINT")
    or (os.getenv("AZURE_AI_AGENT_ENDPOINT", "").split("/api/projects")[0] or None)
)
AZURE_AI_SEARCH_ENDPOINT = os.getenv("AZURE_AI_SEARCH_ENDPOINT")

# Models
EMBEDDING_MODEL = (
    os.getenv("AZURE_OPENAI_EMBEDDING_MODEL")
    or os.getenv("EMBEDDING_MODEL", "text-embedding-3-small")
)

# Solution name (used for naming the index, KB, etc.)
SOLUTION_NAME = (
    os.getenv("SOLUTION_NAME")
    or os.getenv("AZURE_ENV_NAME", "demo")
)

# Index name — override via env or auto-generate
INDEX_NAME = os.getenv("AZURE_AI_SEARCH_INDEX") or f"{SOLUTION_NAME}-documents"

# Chunking parameters
CHUNK_SIZE = 1000     # Max characters per chunk
CHUNK_OVERLAP = 200   # Overlap between chunks (for context continuity)

# ============================================================================
# Validation
# ============================================================================

if not AZURE_AI_SEARCH_ENDPOINT:
    print("ERROR: AZURE_AI_SEARCH_ENDPOINT not set")
    print("       Run 'azd up' first, or set it in scripts/.env")
    sys.exit(1)

if not AZURE_AI_ENDPOINT:
    print("ERROR: AZURE_AI_ENDPOINT / AZURE_OPENAI_ENDPOINT not set")
    print("       Run 'azd up' first, or set it in scripts/.env")
    sys.exit(1)

# Resolve data folder
try:
    data_dir = Path(get_data_folder())
except ValueError:
    print("ERROR: DATA_FOLDER not set in .env")
    print("       Set DATA_FOLDER=data in scripts/.env")
    sys.exit(1)

docs_dir = data_dir / "documents"
config_dir = data_dir / "config"

if not docs_dir.exists():
    print(f"ERROR: Documents folder not found: {docs_dir}")
    print("       Place your PDF files there, or run 00_generate_sample_docs.py")
    sys.exit(1)

# Ensure config dir exists
config_dir.mkdir(parents=True, exist_ok=True)

print(f"\n{'='*60}")
print("Upload PDFs to Azure AI Search + Create Knowledge Base")
print(f"{'='*60}")
print(f"Search Endpoint : {AZURE_AI_SEARCH_ENDPOINT}")
print(f"AI Endpoint     : {AZURE_AI_ENDPOINT}")
print(f"Embedding Model : {EMBEDDING_MODEL}")
print(f"Index Name      : {INDEX_NAME}")
print(f"Documents Folder: {docs_dir}")

# ============================================================================
# Azure OpenAI Client (for embeddings)
# ============================================================================

def get_openai_client() -> AzureOpenAI:
    """Create an Azure OpenAI client using DefaultAzureCredential."""
    credential = DefaultAzureCredential()
    token = credential.get_token("https://cognitiveservices.azure.com/.default")
    return AzureOpenAI(
        azure_endpoint=AZURE_AI_ENDPOINT,
        api_key=token.token,
        api_version="2024-10-21",
    )


def get_embedding(client: AzureOpenAI, text: str) -> list[float]:
    """Generate an embedding vector for a text string."""
    response = client.embeddings.create(input=[text], model=EMBEDDING_MODEL)
    return response.data[0].embedding

# ============================================================================
# Azure Search Clients
# ============================================================================

def get_search_clients():
    """Create the index admin client and document upload client."""
    credential = DefaultAzureCredential()
    index_client = SearchIndexClient(AZURE_AI_SEARCH_ENDPOINT, credential)
    search_client = SearchClient(AZURE_AI_SEARCH_ENDPOINT, INDEX_NAME, credential)
    return index_client, search_client

# ============================================================================
# Create Search Index
# ============================================================================

def create_index(index_client: SearchIndexClient):
    """Create (or update) the search index with vector search + semantic config.

    Fields:
      - id (key)        : Unique document chunk ID
      - content         : The text chunk (searchable)
      - title           : PDF file name (filterable)
      - source          : Original PDF filename
      - page_number     : Page the chunk came from
      - chunk_id        : Chunk number within the page
      - embedding       : Vector embedding for hybrid search
    """
    # Embedding dimensions vary by model
    DIMS = {
        "text-embedding-ada-002": 1536,
        "text-embedding-3-small": 1536,
        "text-embedding-3-large": 3072,
    }
    dimensions = DIMS.get(EMBEDDING_MODEL, 1536)

    fields = [
        SearchField(name="id", type=SearchFieldDataType.String, key=True),
        SearchField(name="content", type=SearchFieldDataType.String, searchable=True),
        SearchField(name="title", type=SearchFieldDataType.String, searchable=True, filterable=True),
        SearchField(name="source", type=SearchFieldDataType.String, filterable=True),
        SearchField(name="page_number", type=SearchFieldDataType.Int32, filterable=True, sortable=True),
        SearchField(name="chunk_id", type=SearchFieldDataType.Int32, sortable=True),
        SearchField(
            name="embedding",
            type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
            searchable=True,
            vector_search_dimensions=dimensions,
            vector_search_profile_name="default-profile",
        ),
    ]

    # Integrated vectorizer — AI Search calls your embedding model at query time
    vectorizer = AzureOpenAIVectorizer(
        vectorizer_name="openai-vectorizer",
        parameters=AzureOpenAIVectorizerParameters(
            resource_url=AZURE_AI_ENDPOINT,
            deployment_name=EMBEDDING_MODEL,
            model_name=EMBEDDING_MODEL,
        ),
    )

    vector_search = VectorSearch(
        algorithms=[HnswAlgorithmConfiguration(name="default-algorithm")],
        profiles=[
            VectorSearchProfile(
                name="default-profile",
                algorithm_configuration_name="default-algorithm",
                vectorizer_name="openai-vectorizer",
            )
        ],
        vectorizers=[vectorizer],
    )

    # Semantic configuration for hybrid (keyword + vector + reranking) search
    semantic_config = SemanticConfiguration(
        name="default-semantic",
        prioritized_fields=SemanticPrioritizedFields(
            content_fields=[SemanticField(field_name="content")],
            title_field=SemanticField(field_name="title"),
        ),
    )
    semantic_search = SemanticSearch(configurations=[semantic_config])

    index = SearchIndex(
        name=INDEX_NAME,
        fields=fields,
        vector_search=vector_search,
        semantic_search=semantic_search,
    )

    index_client.create_or_update_index(index)
    print(f"[OK] Index '{INDEX_NAME}' ready (vector + semantic)")

# ============================================================================
# PDF Processing + Chunking
# ============================================================================

def extract_pages_from_pdf(filepath: Path) -> list[tuple[int, str]]:
    """Extract text from each page of a PDF. Returns [(page_num, text), ...]."""
    reader = PdfReader(filepath)
    pages = []
    for i, page in enumerate(reader.pages):
        text = page.extract_text()
        if text and text.strip():
            pages.append((i + 1, text.strip()))
    return pages


def split_into_sentences(text: str) -> list[str]:
    """Split text into sentences at punctuation boundaries."""
    sentences = re.split(r'(?<=[.!?])\s+', text)
    return [s.strip() for s in sentences if s.strip()]


def chunk_text(text: str, max_size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[str]:
    """Split text into chunks that respect sentence boundaries.

    - Chunks won't exceed max_size characters
    - Sentences are never split mid-sentence
    - Overlap sentences are carried into the next chunk for context
    """
    sentences = split_into_sentences(text)
    if not sentences:
        return [text] if text.strip() else []

    chunks = []
    current = []
    current_len = 0
    overlap_buf = []

    for sentence in sentences:
        slen = len(sentence)

        # Oversized single sentence — keep it whole
        if slen > max_size:
            if current:
                chunks.append(" ".join(current))
                overlap_buf = current[-2:] if len(current) >= 2 else current[:]
            chunks.append(sentence)
            current, current_len, overlap_buf = [], 0, []
            continue

        potential = current_len + slen + (1 if current else 0)
        if potential > max_size and current:
            chunks.append(" ".join(current))
            # Start next chunk with overlap
            ovl_len = sum(len(s) for s in overlap_buf) + len(overlap_buf)
            if ovl_len < overlap and overlap_buf:
                current = overlap_buf[:]
                current_len = ovl_len
            else:
                current, current_len = [], 0

        current.append(sentence)
        current_len += slen + (1 if len(current) > 1 else 0)
        overlap_buf = current[-2:] if len(current) >= 2 else current[:]

    if current:
        chunks.append(" ".join(current))

    return chunks

# ============================================================================
# Main
# ============================================================================

def main():
    # Discover PDFs
    pdf_files = sorted(docs_dir.glob("*.pdf"))
    if not pdf_files:
        print(f"\nNo PDF files found in {docs_dir}")
        print("  Run: python 00_generate_sample_docs.py")
        print("  Or place your own PDFs in data/documents/")
        return

    print(f"\nFound {len(pdf_files)} PDF(s):")
    for p in pdf_files:
        print(f"  - {p.name}")

    # Init clients
    print("\nInitializing clients...")
    openai_client = get_openai_client()
    print("[OK] OpenAI client ready")

    index_client, search_client = get_search_clients()
    print("[OK] Search clients ready")

    # Create or update the search index
    print("\nCreating search index...")
    create_index(index_client)

    # Process PDFs → chunks → embeddings → upload
    documents = []
    for pdf_path in pdf_files:
        print(f"\nProcessing: {pdf_path.name}")
        pages = extract_pages_from_pdf(pdf_path)
        print(f"  {len(pages)} pages extracted")

        for page_num, page_text in pages:
            chunks = chunk_text(page_text)
            for chunk_idx, chunk in enumerate(chunks):
                doc_id = f"{pdf_path.stem}_p{page_num}_c{chunk_idx}"
                print(f"  Embedding {doc_id}...", end=" ", flush=True)
                embedding = get_embedding(openai_client, chunk)
                print("OK")

                documents.append({
                    "id": doc_id,
                    "content": chunk,
                    "title": pdf_path.stem.replace("_", " ").title(),
                    "source": pdf_path.name,
                    "page_number": page_num,
                    "chunk_id": chunk_idx,
                    "embedding": embedding,
                })

    # Upload to search index
    print(f"\nUploading {len(documents)} chunks to index '{INDEX_NAME}'...")
    result = search_client.upload_documents(documents)
    succeeded = sum(1 for r in result if r.succeeded)
    print(f"[OK] {succeeded}/{len(documents)} chunks uploaded")

    # ================================================================
    # Create Foundry IQ Knowledge Source + Knowledge Base
    # ================================================================

    KB_NAME = f"{SOLUTION_NAME}-kb"
    KS_NAME = f"{SOLUTION_NAME}-ks"

    # Knowledge Source — tells Foundry IQ which search index to use
    print(f"\nCreating Knowledge Source '{KS_NAME}'...")
    try:
        ks = SearchIndexKnowledgeSource(
            name=KS_NAME,
            description=f"Document search index for {SOLUTION_NAME}",
            search_index_parameters=SearchIndexKnowledgeSourceParameters(
                search_index_name=INDEX_NAME,
                semantic_configuration_name="default-semantic",
                source_data_fields=[
                    SearchIndexFieldReference(name="title"),
                    SearchIndexFieldReference(name="source"),
                ],
                search_fields=[
                    SearchIndexFieldReference(name="content"),
                ],
            ),
        )
        index_client.create_or_update_knowledge_source(ks)
        print(f"[OK] Knowledge Source '{KS_NAME}' created")
    except Exception as e:
        print(f"[WARN] Could not create Knowledge Source: {e}")
        print("       You can create it manually in the Azure portal.")

    # Knowledge Base — wraps the source with AI-powered retrieval
    print(f"\nCreating Knowledge Base '{KB_NAME}'...")
    try:
        chat_model = (
            os.getenv("AZURE_OPENAI_CHAT_MODEL")
            or os.getenv("AZURE_CHAT_MODEL")
            or os.getenv("AZURE_AI_AGENT_MODEL_DEPLOYMENT_NAME", "gpt-4o-mini")
        )
        aoai_params = AzureOpenAIVectorizerParameters(
            resource_url=AZURE_AI_ENDPOINT,
            deployment_name=chat_model,
            model_name=chat_model,
        )
        kb = KnowledgeBase(
            name=KB_NAME,
            description=f"Knowledge base for {SOLUTION_NAME} — document retrieval with agentic query planning.",
            retrieval_instructions=(
                "Use this knowledge source for questions about policies, guidelines, "
                "thresholds, rules, procedures, and reference documents."
            ),
            answer_instructions=(
                "Provide a concise, informative answer based on the retrieved documents. "
                "Always cite the source document name."
            ),
            output_mode=KnowledgeRetrievalOutputMode.ANSWER_SYNTHESIS,
            knowledge_sources=[KnowledgeSourceReference(name=KS_NAME)],
            models=[KnowledgeBaseAzureOpenAIModel(azure_open_ai_parameters=aoai_params)],
            retrieval_reasoning_effort=KnowledgeRetrievalLowReasoningEffort,
        )
        index_client.create_or_update_knowledge_base(kb)
        print(f"[OK] Knowledge Base '{KB_NAME}' created")
    except Exception as e:
        print(f"[WARN] Could not create Knowledge Base: {e}")
        print("       You can create it manually in the Azure portal.")

    # Save config for downstream scripts
    search_ids = {
        "index_name": INDEX_NAME,
        "knowledge_base_name": KB_NAME,
        "knowledge_source_name": KS_NAME,
        "document_count": len(documents),
        "pdf_files": [p.name for p in pdf_files],
    }
    ids_path = config_dir / "search_ids.json"
    with open(ids_path, "w") as f:
        json.dump(search_ids, f, indent=2)
    print(f"[OK] Config saved to {ids_path}")

    print(f"\n{'='*60}")
    print("Upload Complete!")
    print(f"{'='*60}")
    print(f"  Index           : {INDEX_NAME}")
    print(f"  Chunks uploaded : {len(documents)}")
    print(f"  Knowledge Source: {KS_NAME}")
    print(f"  Knowledge Base  : {KB_NAME}")
    print(f"\nNext step:")
    print(f"  python 02_create_agent.py")


if __name__ == "__main__":
    main()
