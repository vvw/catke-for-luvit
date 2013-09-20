local Object = require('core').Object
local utils  = require('../utils')
local Array  = require('../base').Array
local timer  = require('timer')

local PostgresLuvit 

local _connects     = nil
local _queue        = Array:new()
local _queue_starts = Array:new()
local _quere_time   = false
local Postgres      = Object:extend()

function Postgres:initialize(setting, lib_path)
	setting = utils.extend({
		dbname = 'test',
		host = '127.0.0.1',
		port = '5432',
		user = '',
		password = '',
		size = 40
	}, (setting or {}))

	self.setting = setting

	_G.POSTGRESQL_LIBRARY_PATH = lib_path or '/usr/lib/libpq.5.dylib'
	PostgresLuvit = require('luvit-postgres/postgresLuvit')

	self._dsn = 'dbname=' .. setting['dbname'] .. ' host=' .. setting['host'] .. ' port=' .. setting['port'] 

	
	if setting['user'] ~= '' then
		self._dsn = self._dsn .. ' user=' .. setting['user'] 
	end

	if setting['password'] ~= '' then
		self._dsn = self._dsn .. ' password=' .. setting['password'] 
	end

end


function Postgres:connect(callback)

	local this = self
	if nil == _connects then
		local pooling = Array:new()
		local i
		for i = 1, this.setting['size'] do
			_queue:append(Array:new())
			_queue_starts:append(0)

			local p_ix = pooling:length() + 1
			
			local postgres = PostgresLuvit:new(this._dsn, function(err)
				pooling:get(p_ix).state = true
				if err then
					error(err)
				end
			end)

			pooling:append({
				state = false,
				con = postgres
			})
			--p(pooling:length())
			if pooling:length() == this.setting['size'] then
				_connects = pooling 
				callback(this)

				-- 开始一个时间队列
				_quere_time = timer.setInterval(5, function()
					_queue_starts:each(function(start, ix)
						-- 队列没有执行查询
						if 0 == start and pooling:get(ix).state then
							local tasks = _queue:get(ix)
							if tasks:length() > 0 then
								local con  = pooling:get(ix).con
								local task = tasks:get(1)
								_queue_starts:set(ix, 1) -- 设置状态为查询

								con:sendQuery(task.sql, function(err, result)
									tasks = _queue:get(ix)
									tasks:remove(task)
									_queue:set(ix, tasks)
																	
									_queue_starts:set(ix, 0) -- 改变状态
									task.callback(err, result)
								end)
							end
						end
					end)
				end)

			end

		end
		
		return
	end

	callback(self)
end

local _task_count = 0
local function add_task(sql, callback)
	local min_count = nil
	local pooling_ix

	_task_count = _task_count + 1

	_queue:each(function(tasks, index)
		local len = tasks:length()

		if 0 == len then
			pooling_ix = index
			return false
		elseif nil == min_count or len < min_count then
			min_count  = len
			pooling_ix = index
		end
	end)

	local task = {
		id = _task_count,
		sql = sql,
		callback = callback 
	}

	_queue:get(pooling_ix):append(task)

end


function Postgres:execute(sql, callback)
	if _connects then
		add_task(sql, callback)
		return
	end

	Postgres:connect(function(con)
		add_task(sql, callback)
	end)
end

return Postgres