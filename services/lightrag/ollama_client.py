"""
Ollama Client Integration for LightRAG

This module provides Ollama integration for local LLM inference,
allowing LightRAG to use local models instead of OpenAI API.
"""

import asyncio
import logging
import httpx
from typing import List, Dict, Any, Optional, AsyncGenerator
from pydantic import BaseModel

logger = logging.getLogger(__name__)


class OllamaModel(BaseModel):
    """Ollama model information"""
    name: str
    modified_at: str
    size: int
    digest: str
    details: Dict[str, Any]


class OllamaClient:
    """Async Ollama API client for LightRAG integration"""
    
    def __init__(
        self,
        base_url: str = "http://ollama:11434",
        timeout: float = 300.0,
        max_retries: int = 3
    ):
        self.base_url = base_url.rstrip('/')
        self.timeout = timeout
        self.max_retries = max_retries
        self._client = httpx.AsyncClient(
            timeout=httpx.Timeout(timeout),
            limits=httpx.Limits(max_connections=10, max_keepalive_connections=5)
        )
    
    async def __aenter__(self):
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self._client.aclose()
    
    async def health_check(self) -> bool:
        """Check if Ollama server is healthy"""
        try:
            response = await self._client.get(f"{self.base_url}/api/tags")
            return response.status_code == 200
        except Exception as e:
            logger.error(f"Ollama health check failed: {e}")
            return False
    
    async def list_models(self) -> List[OllamaModel]:
        """List available models"""
        try:
            response = await self._client.get(f"{self.base_url}/api/tags")
            response.raise_for_status()
            
            data = response.json()
            return [OllamaModel(**model) for model in data.get("models", [])]
        
        except Exception as e:
            logger.error(f"Failed to list models: {e}")
            return []
    
    async def pull_model(self, model_name: str, stream: bool = True) -> bool:
        """Pull/download a model"""
        try:
            payload = {"name": model_name, "stream": stream}
            
            async with self._client.stream(
                "POST",
                f"{self.base_url}/api/pull",
                json=payload,
                timeout=self.timeout
            ) as response:
                response.raise_for_status()
                
                if stream:
                    async for chunk in response.aiter_lines():
                        if chunk:
                            try:
                                import json
                                data = json.loads(chunk)
                                if data.get("status"):
                                    logger.info(f"Pull status: {data['status']}")
                                if data.get("error"):
                                    logger.error(f"Pull error: {data['error']}")
                                    return False
                            except json.JSONDecodeError:
                                continue
                
                return True
                
        except Exception as e:
            logger.error(f"Failed to pull model {model_name}: {e}")
            return False
    
    async def check_model_exists(self, model_name: str) -> bool:
        """Check if a model exists locally"""
        models = await self.list_models()
        return any(model.name == model_name for model in models)
    
    async def generate_completion(
        self,
        model: str,
        prompt: str,
        system: Optional[str] = None,
        temperature: float = 0.7,
        max_tokens: int = 512,
        top_k: int = 40,
        top_p: float = 0.9,
        stream: bool = False,
        **kwargs
    ) -> str:
        """Generate text completion"""
        try:
            # Ensure model exists
            if not await self.check_model_exists(model):
                logger.info(f"Model {model} not found, attempting to pull...")
                if not await self.pull_model(model):
                    raise Exception(f"Failed to pull model {model}")
            
            # Prepare messages format
            messages = []
            if system:
                messages.append({"role": "system", "content": system})
            messages.append({"role": "user", "content": prompt})
            
            payload = {
                "model": model,
                "messages": messages,
                "stream": stream,
                "options": {
                    "temperature": temperature,
                    "num_predict": max_tokens,
                    "top_k": top_k,
                    "top_p": top_p,
                    **kwargs
                }
            }
            
            if stream:
                return await self._generate_streaming(payload)
            else:
                return await self._generate_non_streaming(payload)
                
        except Exception as e:
            logger.error(f"Failed to generate completion: {e}")
            raise
    
    async def _generate_non_streaming(self, payload: Dict[str, Any]) -> str:
        """Generate non-streaming completion"""
        response = await self._client.post(
            f"{self.base_url}/api/chat",
            json=payload,
            timeout=self.timeout
        )
        response.raise_for_status()
        
        data = response.json()
        return data["message"]["content"]
    
    async def _generate_streaming(self, payload: Dict[str, Any]) -> str:
        """Generate streaming completion"""
        full_response = ""
        
        async with self._client.stream(
            "POST",
            f"{self.base_url}/api/chat",
            json=payload,
            timeout=self.timeout
        ) as response:
            response.raise_for_status()
            
            async for chunk in response.aiter_lines():
                if chunk:
                    try:
                        import json
                        data = json.loads(chunk)
                        
                        if "message" in data:
                            content = data["message"].get("content", "")
                            full_response += content
                        
                        if data.get("done", False):
                            break
                            
                    except json.JSONDecodeError:
                        continue
        
        return full_response
    
    async def generate_embeddings(
        self,
        model: str,
        texts: List[str],
        **kwargs
    ) -> List[List[float]]:
        """Generate embeddings for texts"""
        try:
            # Ensure model exists
            if not await self.check_model_exists(model):
                logger.info(f"Embedding model {model} not found, attempting to pull...")
                if not await self.pull_model(model):
                    raise Exception(f"Failed to pull embedding model {model}")
            
            embeddings = []
            
            for text in texts:
                payload = {
                    "model": model,
                    "prompt": text,
                    **kwargs
                }
                
                response = await self._client.post(
                    f"{self.base_url}/api/embeddings",
                    json=payload,
                    timeout=self.timeout
                )
                response.raise_for_status()
                
                data = response.json()
                embeddings.append(data["embedding"])
            
            return embeddings
            
        except Exception as e:
            logger.error(f"Failed to generate embeddings: {e}")
            raise


class OllamaLightRAGIntegration:
    """Integration layer between Ollama and LightRAG"""
    
    def __init__(
        self,
        client: OllamaClient,
        llm_model: str = "llama2:7b",
        embedding_model: str = "nomic-embed-text",
        max_tokens: int = 512,
        temperature: float = 0.7,
        **model_params
    ):
        self.client = client
        self.llm_model = llm_model
        self.embedding_model = embedding_model
        self.max_tokens = max_tokens
        self.temperature = temperature
        self.model_params = model_params
    
    async def llm_complete(
        self,
        prompt: str,
        system_prompt: Optional[str] = None,
        history_messages: List[Dict[str, str]] = None,
        **kwargs
    ) -> str:
        """LightRAG-compatible LLM completion function"""
        try:
            # Merge parameters
            params = {
                "temperature": self.temperature,
                "max_tokens": self.max_tokens,
                **self.model_params,
                **kwargs
            }
            
            # Generate completion
            response = await self.client.generate_completion(
                model=self.llm_model,
                prompt=prompt,
                system=system_prompt,
                **params
            )
            
            return response
            
        except Exception as e:
            logger.error(f"Ollama LLM completion failed: {e}")
            # Return a fallback response or re-raise based on requirements
            raise
    
    async def embedding_complete(
        self,
        texts: List[str],
        **kwargs
    ) -> List[List[float]]:
        """LightRAG-compatible embedding function"""
        try:
            embeddings = await self.client.generate_embeddings(
                model=self.embedding_model,
                texts=texts,
                **kwargs
            )
            
            return embeddings
            
        except Exception as e:
            logger.error(f"Ollama embedding generation failed: {e}")
            raise


# Factory functions for LightRAG integration
async def create_ollama_llm_func(
    base_url: str = "http://ollama:11434",
    model: str = "llama2:7b",
    temperature: float = 0.7,
    max_tokens: int = 512,
    **kwargs
):
    """Create Ollama LLM function for LightRAG"""
    client = OllamaClient(base_url=base_url)
    integration = OllamaLightRAGIntegration(
        client=client,
        llm_model=model,
        temperature=temperature,
        max_tokens=max_tokens,
        **kwargs
    )
    
    async def llm_func(prompt, system_prompt=None, history_messages=None, **func_kwargs):
        return await integration.llm_complete(
            prompt=prompt,
            system_prompt=system_prompt,
            history_messages=history_messages or [],
            **func_kwargs
        )
    
    return llm_func


async def create_ollama_embedding_func(
    base_url: str = "http://ollama:11434",
    model: str = "nomic-embed-text",
    **kwargs
):
    """Create Ollama embedding function for LightRAG"""
    client = OllamaClient(base_url=base_url)
    integration = OllamaLightRAGIntegration(
        client=client,
        embedding_model=model,
        **kwargs
    )
    
    async def embedding_func(texts, **func_kwargs):
        return await integration.embedding_complete(
            texts=texts,
            **func_kwargs
        )
    
    return embedding_func