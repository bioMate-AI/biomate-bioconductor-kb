#!/usr/bin/env python3
import argparse
import requests
import json
import sys
import os

def call_sentiment_api(input_file, output_file, api_endpoint, api_key, confidence_threshold=0.5):
    """
    调用REST API进行情感分析
    """
    try:
        # 读取输入文件
        with open(input_file, 'r', encoding='utf-8') as f:
            text_content = f.read()
        
        # 准备API请求
        headers = {
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {api_key}'
        }
        
        payload = {
            'text': text_content,
            'threshold': confidence_threshold
        }
        
        # 发送API请求
        response = requests.post(
            api_endpoint,
            headers=headers,
            json=payload,
            timeout=30
        )
        
        # 检查响应状态
        if response.status_code == 200:
            result = response.json()
            
            # 写入输出文件
            with open(output_file, 'w', encoding='utf-8') as f:
                json.dump(result, f, indent=2, ensure_ascii=False)
            
            print(f"Sentiment analysis completed successfully")
            print(f"Results saved to: {output_file}")
            
        else:
            error_msg = f"API request failed with status {response.status_code}: {response.text}"
            print(error_msg, file=sys.stderr)
            sys.exit(1)
            
    except requests.exceptions.RequestException as e:
        print(f"Network error: {str(e)}", file=sys.stderr)
        sys.exit(1)
    except FileNotFoundError:
        print(f"Input file not found: {input_file}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {str(e)}", file=sys.stderr)
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(description='Call sentiment analysis REST API')
    parser.add_argument('--input', required=True, help='Input text file')
    parser.add_argument('--output', required=True, help='Output JSON file')
    parser.add_argument('--api_endpoint', required=True, help='API endpoint URL')
    parser.add_argument('--api_key', required=True, help='API authentication key')
    parser.add_argument('--confidence_threshold', type=float, default=0.5, 
                       help='Confidence threshold for sentiment classification')
    
    args = parser.parse_args()
    
    # 调用API
    call_sentiment_api(
        args.input,
        args.output,
        args.api_endpoint,
        args.api_key,
        args.confidence_threshold
    )

if __name__ == '__main__':
    main()