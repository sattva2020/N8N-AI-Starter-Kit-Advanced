# Supabase Integration Guide

This guide explains how to integrate Supabase into the N8N AI Starter Kit using a hybrid database approach.

## 🏗️ Hybrid Database Architecture

The N8N AI Starter Kit implements a hybrid database architecture that separates concerns between core application data and AI/analytics data:

- **Local PostgreSQL**: Handles core N8N application data (workflows, credentials, execution history)
- **Supabase**: Manages AI/analytics data (document processing results, embeddings, knowledge graphs)

This approach provides several benefits:
- Optimal performance for core N8N operations
- Scalable storage for AI workloads
- Independent scaling of data services
- Cloud-native capabilities for analytics

## 🚀 Quick Setup

### 1. Create a Supabase Project

1. Go to [https://app.supabase.com](https://app.supabase.com)
2. Sign up or log in to your account
3. Create a new project
4. Note your project URL and API key

### 2. Configure Environment Variables

Add the following to your `.env` file:

```bash
# Supabase Configuration
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_KEY=your-anon-or-service-key

# Enable Supabase profile
COMPOSE_PROFILES=default,developer,monitoring,supabase
```

### 3. Start Services

```bash
./start.sh
```

## 📊 Data Structure

Supabase tables are organized to support different AI/analytics workloads:

### AI Results Table (`ai_results`)
Stores results from AI processing services:
- `id` (UUID): Unique identifier
- `service_name` (text): Name of the AI service
- `input_data` (jsonb): Input data that was processed
- `output_data` (jsonb): AI-generated output
- `processing_time` (numeric): Time taken for processing
- `created_at` (timestamp): When the result was created

### Document Embeddings Table (`document_embeddings`)
Stores vector embeddings for document processing:
- `id` (UUID): Unique identifier
- `document_id` (UUID): Reference to the source document
- `content` (text): Extracted content
- `embedding` (vector): Vector representation
- `metadata` (jsonb): Additional metadata
- `created_at` (timestamp): When the embedding was created

### Analytics Table (`ai_analytics`)
Stores analytics data from AI services:
- `id` (UUID): Unique identifier
- `service_name` (text): Name of the AI service
- `metric_name` (text): Name of the metric
- `metric_value` (numeric): Value of the metric
- `tags` (jsonb): Additional tags for filtering
- `timestamp` (timestamp): When the metric was recorded

## 🔧 Service Integration

AI services in the kit can be configured to use Supabase for data storage:

### Document Processor
The document processor can store processing results and embeddings in Supabase tables.

### LightRAG
LightRAG can store knowledge graphs and retrieval results in Supabase.

### ETL Processor
The ETL processor can store analytics data in Supabase for advanced querying.

## 🛡️ Security Considerations

1. **API Keys**: Store Supabase keys securely and rotate them regularly
2. **Row Level Security**: Enable RLS in Supabase for fine-grained access control
3. **Service Keys**: Use service keys for backend operations, not anon keys
4. **Connection Pooling**: Consider using connection pooling for high-volume services

## 📈 Monitoring and Scaling

Supabase provides built-in monitoring through the Supabase dashboard:
- Query performance metrics
- Database size and growth
- Connection usage
- Error rates

For scaling:
- Upgrade your Supabase plan as data grows
- Use Supabase's auto-scaling features
- Implement caching for frequently accessed data

## 🔄 Data Synchronization

For scenarios where you need to synchronize data between local PostgreSQL and Supabase:

1. Use Supabase's Realtime features for live updates
2. Implement scheduled sync jobs using the ETL processor
3. Consider using database triggers for automatic synchronization

## 🧪 Testing

To test Supabase integration:

1. Run the test suite with Supabase profile enabled:
   ```bash
   COMPOSE_PROFILES=default,developer,monitoring,supabase ./start.sh --test
   ```

2. Verify data is being written to Supabase tables
3. Check that AI services can read from Supabase when needed

## 🆘 Troubleshooting

### Common Issues

1. **Connection Errors**: Verify SUPABASE_URL and SUPABASE_KEY in .env
2. **Permission Errors**: Check that your Supabase key has the necessary permissions
3. **Table Not Found**: Ensure tables are created in Supabase dashboard

### Debugging Steps

1. Check service logs:
   ```bash
   docker-compose logs document-processor
   ```

2. Verify environment variables:
   ```bash
   docker-compose exec document-processor env | grep SUPABASE
   ```

3. Test Supabase connection:
   ```bash
   curl -H "apikey: $SUPABASE_KEY" $SUPABASE_URL/rest/v1/
   ```

## 📚 Additional Resources

- [Supabase Documentation](https://supabase.com/docs)
- [Supabase Python Client](https://supabase.com/docs/guides/getting-started/tutorials/with-python)
- [N8N AI Starter Kit Documentation](./README.md)