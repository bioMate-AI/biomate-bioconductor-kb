#!/usr/bin/env python3
"""
PDF Reader Script
Extracts text content from PDF files using PyMuPDF (fitz)
"""

import fitz  # PyMuPDF
import sys
from pathlib import Path


def read_pdf(pdf_path: str, output_txt: str = None) -> str:
    """
    Read a PDF file and extract all text content.
    
    Args:
        pdf_path: Path to the PDF file
        output_txt: Optional path to save extracted text
        
    Returns:
        Extracted text as a string
    """
    pdf_path = Path(pdf_path)
    
    if not pdf_path.exists():
        raise FileNotFoundError(f"PDF file not found: {pdf_path}")
    
    # Open the PDF
    doc = fitz.open(str(pdf_path))
    
    print(f"📄 PDF Info:")
    print(f"   - File: {pdf_path.name}")
    print(f"   - Size: {pdf_path.stat().st_size / (1024*1024):.2f} MB")
    print(f"   - Pages: {len(doc)}")
    print(f"   - Metadata: {doc.metadata}")
    print("-" * 60)
    
    # Extract text from all pages
    full_text = []
    
    for page_num in range(len(doc)):
        page = doc[page_num]
        text = page.get_text()
        
        if text.strip():
            full_text.append(f"\n{'='*60}")
            full_text.append(f"PAGE {page_num + 1}")
            full_text.append(f"{'='*60}\n")
            full_text.append(text)
    
    doc.close()
    
    result = "\n".join(full_text)
    
    # Optionally save to file
    if output_txt:
        output_path = Path(output_txt)
        output_path.write_text(result, encoding='utf-8')
        print(f"✅ Text saved to: {output_path}")
    
    return result


def read_pdf_by_page(pdf_path: str) -> list:
    """
    Read a PDF file and return text as a list of pages.
    
    Args:
        pdf_path: Path to the PDF file
        
    Returns:
        List of strings, one per page
    """
    doc = fitz.open(pdf_path)
    pages = []
    
    for page_num in range(len(doc)):
        page = doc[page_num]
        pages.append({
            'page_num': page_num + 1,
            'text': page.get_text(),
            'images': len(page.get_images()),
            'links': len(page.get_links())
        })
    
    doc.close()
    return pages


def extract_images(pdf_path: str, output_dir: str = "./images"):
    """
    Extract all images from a PDF file.
    
    Args:
        pdf_path: Path to the PDF file
        output_dir: Directory to save extracted images
    """
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)
    
    doc = fitz.open(pdf_path)
    image_count = 0
    
    for page_num in range(len(doc)):
        page = doc[page_num]
        images = page.get_images()
        
        for img_index, img in enumerate(images):
            xref = img[0]
            base_image = doc.extract_image(xref)
            image_bytes = base_image["image"]
            image_ext = base_image["ext"]
            
            image_filename = output_path / f"page{page_num + 1}_img{img_index + 1}.{image_ext}"
            
            with open(image_filename, "wb") as f:
                f.write(image_bytes)
            
            image_count += 1
    
    doc.close()
    print(f"✅ Extracted {image_count} images to {output_path}")
    return image_count


if __name__ == "__main__":
    # Default to the uploaded PDF if no argument provided
    if len(sys.argv) > 1:
        pdf_file = sys.argv[1]
    else:
        pdf_file = "/mnt/user-data/uploads/scientific_llm_benchmark.pdf"
    
    # Read and display the PDF content
    text = read_pdf(pdf_file, output_txt="/home/claude/pdf_content.txt")
    
    # Show first 5000 characters as preview
    print("\n📖 Content Preview (first 5000 chars):")
    print("-" * 60)
    print(text[:5000])
    print("\n..." if len(text) > 5000 else "")
    print(f"\n📊 Total characters extracted: {len(text):,}")
