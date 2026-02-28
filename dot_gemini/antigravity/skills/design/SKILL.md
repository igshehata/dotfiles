---
description: Code-based system design practice with problem-driven learning
---

Initiate an interactive system design coding session following this 9-step problem-based process:

1. **Load Progress**: Scan `r/system design.md` (Interview Practice Systems section) and all `k/System Design - *.md` notes to identify:
   - Which systems have been completed
   - Current system in progress
   - Next recommended system

2. **Setup Boilerplate** (if starting a new system):
   - Copy the boilerplate template: `cp -r _boilerplate/ {system-folder}/`
   - Install dependencies: `cd {system-folder} && bun install`
   - Setup environment: `cp .env.example .env`
   - Start infrastructure: `bun run docker:up` (wait ~10s for health checks)
   - Verify setup: `bun run dev` and `curl http://localhost:3000/health`
   - The boilerplate includes:
     - **Bun** + TypeScript runtime
     - **Express** web framework (familiar, battle-tested)
     - **Drizzle ORM** with PostgreSQL (supports raw SQL for learning)
     - **Redis** for caching
     - **Docker Compose** for infrastructure
     - Health check endpoint
     - Test setup with Bun test
   - See `_boilerplate/README.md` for full documentation

3. **Present System Challenge**: Introduce the next system to design and implement:
   - System name and real-world examples (e.g., "URL Shortener like Bitly/TinyURL")
   - Problem statement
   - Functional requirements
   - Non-functional requirements (QPS, availability, latency)
   - Show ALL micro-tasks for the system (8-12 tasks)

4. **Decompose into Micro-Tasks**: Break the system into small, implementable coding tasks:
   - Each task is a concrete coding step (15-45 minutes)
   - Tasks build on each other incrementally
   - Focus on ONE concept per task
   - **NOTE**: Task 1 is always boilerplate setup (covered in step 2)
   - Example for URL Shortener:
     - Task 1: Setup boilerplate (Bun + Express + Drizzle + Docker)
     - Task 2: Implement Base62 encoding function for URL shortening
     - Task 3: Create database schema for URLs table with Drizzle
     - Task 4: POST /shorten endpoint - accept long URL, return short code
     - Task 5: GET /:shortCode endpoint - redirect to original URL
     - Task 6: Handle hash collisions with counter approach
     - Task 7: Add input validation (URL format, length limits)
     - Task 8: Implement simple rate limiting middleware
     - Task 9: Add Redis caching layer for popular URLs (LRU strategy)
     - Task 10: Track click analytics (count, last accessed timestamp)
     - Task 11: Write comprehensive tests for all endpoints
     - Task 12: Add monitoring and observability (metrics, logging)

5. **User Codes Task**: Guide the user through implementing ONE task at a time:
   - Clarify the specific requirement
   - Suggest approach if needed
   - Review code as they write it
   - Ensure task is fully working before moving to next
   - Use `bun run dev` for development server with hot reload
   - Use `bun test` to run tests after implementation

6. **Review Code**: After each task:
   - Analyze implementation for correctness
   - Suggest improvements (performance, readability, edge cases)
   - Run/test the code using Bun
   - Verify database queries using Drizzle Studio: `bun run db:studio`
   - Check Redis state using: `docker exec -it system-design-redis redis-cli`
   - Ensure it integrates with previous tasks

7. **Teach Concept Just-In-Time**: Explain the system design principle demonstrated by this task:
   - Why this approach was chosen
   - Tradeoffs involved
   - How it scales
   - Alternatives and when to use them
   - Real-world examples from production systems (Bitly, Stripe, Netflix, etc.)
   - When to use raw SQL vs Drizzle's type-safe queries

8. **Connect to L6 Thinking**: Discuss implications at scale:
   - What breaks at 10x, 100x, 1000x load?
   - Cost implications (compute, storage, network) with AWS estimates
   - Operational complexity and monitoring needs
   - Connect to user's production experience (30M users, M-Pesa, 4 markets)
   - Database indexing strategies for production
   - Redis caching patterns at scale (cache hit ratio, eviction policies)

9. **Update Progress**: After completing a task:
   - Update the `k/System Design - [System].md` note with task completion
   - Update properties (completed-tasks count, status)
   - Commit code to repo with descriptive message
   - When all tasks for a system are done, suggest next system

**Repository Structure**:
All code lives in: `/Users/islam.shehata/personal/system-design-practice/`

```
system-design-practice/
├── _boilerplate/              # Template for all systems (copy this!)
│   ├── src/
│   │   ├── index.ts          # Express server entry point
│   │   ├── db/
│   │   │   ├── index.ts      # Drizzle connection
│   │   │   └── schema.ts     # Database schema
│   │   ├── routes/           # Express routers
│   │   │   └── health.ts     # Health check endpoint
│   │   └── utils/
│   │       └── redis.ts      # Redis client
│   ├── tests/                # Bun test files
│   ├── docker-compose.yml    # Postgres + Redis
│   ├── package.json          # Bun dependencies
│   ├── tsconfig.json         # TypeScript config
│   ├── drizzle.config.ts     # Drizzle ORM config
│   ├── .env.example          # Environment variables template
│   └── README.md             # Full boilerplate documentation
├── 01-url-shortener/         # Copy of boilerplate + implementation
├── 02-rate-limiter/
├── 03-api-gateway/
└── ... (10 systems total)
```

**Tech Stack**:

- **Runtime**: Bun (fast TypeScript runtime, drop-in Node.js replacement)
- **Framework**: Express (familiar, battle-tested, focus on system design not framework)
- **ORM**: Drizzle (type-safe + raw SQL support for learning)
- **Database**: PostgreSQL 16
- **Cache**: Redis 7
- **Testing**: Bun test (built-in, fast)
- **Infrastructure**: Docker & Docker Compose

**Session Management**:

- Encourage incremental progress (one task per session is fine)
- Maintain educational, patient tone
- Focus on understanding WHY, not just completing tasks
- Draw parallels to user's production experience
- Use Core Thinking Frameworks from CLAUDE.md:
  - Multi-Dimensional Understanding (theory, practice, tradeoffs, evolution)
  - Ladder of Abstraction (concrete example → pattern → meta-pattern → transfer)
  - First Principles Reconstruction

**System Prioritization**:
Prioritize systems related to user's experience:

1. Payment System (M-Pesa experience!)
2. Observability Stack (DataDog/LogLayer work)
3. Multi-Region Service (4 markets architecture)
4. API Gateway (TMF integrations)
5. Rate Limiter (security work)
6. Then: URL Shortener, Distributed Cache, Notification System, CDN, Newsfeed

**Difficulty Progression**:

- Start with beginner systems (URL Shortener) to learn patterns
- Progress to intermediate (Rate Limiter, API Gateway)
- Finish with advanced (Payment System, Multi-Region) where user can leverage production experience
