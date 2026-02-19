# ============================================================
# Lambda Deployment Makefile
#
# Usage:
#   make batch   — build + deploy batch_event_handler
#   make s3      — build + deploy s3_event_handler
#   make all     — build + deploy both
#   make clean   — remove build artifacts
#
# Prerequisites:
#   AWS CLI configured with deploy permissions
#   BILLING_API_URL, BILLING_INTERNAL_KEY set in environment or passed as:
#     make batch BILLING_API_URL=http://... BILLING_INTERNAL_KEY=secret
# ============================================================

AWS_REGION        ?= us-east-1
LAMBDA_ROLE_ARN   ?= arn:aws:iam::$(AWS_ACCOUNT_ID):role/biomate-lambda-billing-role
BILLING_API_URL   ?= http://biomate-internal-alb:8081
BILLING_INTERNAL_KEY ?= change-me-in-production

BATCH_FUNCTION    = biomate-batch-billing
S3_FUNCTION       = biomate-s3-billing
RUNTIME           = python3.12
BUILD_DIR         = .build

.PHONY: all batch s3 clean layer

all: batch s3

# ---- Shared layer (httpx) -------------------------------------------------

layer:
	mkdir -p $(BUILD_DIR)/layer/python
	pip install -r requirements.txt -t $(BUILD_DIR)/layer/python --quiet
	cd $(BUILD_DIR)/layer && zip -r ../httpx-layer.zip python/
	aws lambda publish-layer-version \
	    --layer-name biomate-billing-deps \
	    --zip-file fileb://$(BUILD_DIR)/httpx-layer.zip \
	    --compatible-runtimes $(RUNTIME) \
	    --region $(AWS_REGION)
	@echo "Layer ARN written above — set LAYER_ARN= and re-run to attach."

# ---- Batch event handler --------------------------------------------------

$(BUILD_DIR)/batch.zip: batch_event_handler.py
	mkdir -p $(BUILD_DIR)
	cp batch_event_handler.py $(BUILD_DIR)/lambda_function.py
	cd $(BUILD_DIR) && zip batch.zip lambda_function.py

batch: $(BUILD_DIR)/batch.zip
	@echo "Deploying $(BATCH_FUNCTION) to $(AWS_REGION) ..."
	aws lambda create-function \
	    --function-name $(BATCH_FUNCTION) \
	    --runtime $(RUNTIME) \
	    --role $(LAMBDA_ROLE_ARN) \
	    --handler lambda_function.handler \
	    --zip-file fileb://$(BUILD_DIR)/batch.zip \
	    --timeout 30 \
	    --memory-size 128 \
	    --environment "Variables={BILLING_API_URL=$(BILLING_API_URL),BILLING_INTERNAL_KEY=$(BILLING_INTERNAL_KEY)}" \
	    --region $(AWS_REGION) 2>/dev/null || \
	aws lambda update-function-code \
	    --function-name $(BATCH_FUNCTION) \
	    --zip-file fileb://$(BUILD_DIR)/batch.zip \
	    --region $(AWS_REGION)
	@echo "Done: $(BATCH_FUNCTION)"

# ---- S3 event handler -----------------------------------------------------

$(BUILD_DIR)/s3.zip: s3_event_handler.py
	mkdir -p $(BUILD_DIR)
	cp s3_event_handler.py $(BUILD_DIR)/lambda_function.py
	cd $(BUILD_DIR) && zip s3.zip lambda_function.py

s3: $(BUILD_DIR)/s3.zip
	@echo "Deploying $(S3_FUNCTION) to $(AWS_REGION) ..."
	aws lambda create-function \
	    --function-name $(S3_FUNCTION) \
	    --runtime $(RUNTIME) \
	    --role $(LAMBDA_ROLE_ARN) \
	    --handler lambda_function.handler \
	    --zip-file fileb://$(BUILD_DIR)/s3.zip \
	    --timeout 30 \
	    --memory-size 128 \
	    --environment "Variables={BILLING_API_URL=$(BILLING_API_URL),BILLING_INTERNAL_KEY=$(BILLING_INTERNAL_KEY)}" \
	    --region $(AWS_REGION) 2>/dev/null || \
	aws lambda update-function-code \
	    --function-name $(S3_FUNCTION) \
	    --zip-file fileb://$(BUILD_DIR)/s3.zip \
	    --region $(AWS_REGION)
	@echo "Done: $(S3_FUNCTION)"

# ---- Cleanup --------------------------------------------------------------

clean:
	rm -rf $(BUILD_DIR) httpx-layer.zip
