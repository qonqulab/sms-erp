'use client';

import { useState } from 'react';
import { useBranch } from '@/hooks/useBranch';

export default function BranchIndicator() {
  const { activeBranchId, setActiveBranchId, branches, isExecutive, activeBranchName, isLoading } = useBranch();
  const [isOpen, setIsOpen] = useState(false);

  if (isLoading) {
    return (
      <div className="h-8 w-24 animate-pulse rounded-full bg-gray-100" />
    );
  }

  // If not executive, they are locked to their branch - show a permanent badge
  if (!isExecutive) {
    return (
      <div className="flex items-center justify-center rounded-lg border border-emerald-100 bg-emerald-50 px-3 py-1.5">
        <span className="text-[11px] font-bold tracking-wide text-emerald-700 uppercase">
          {activeBranchName}
        </span>
      </div>
    );
  }

  // If Executive, show the interactive context switcher
  return (
    <div className="relative">
      <button
        onClick={() => setIsOpen(!isOpen)}
        className={`flex items-center rounded-lg px-3 py-1.5 text-left transition-colors outline-none ${
          isOpen
            ? 'bg-blue-50 border-blue-200 text-blue-700 shadow-sm ring-2 ring-blue-500/20 ring-offset-1'
            : 'bg-white border border-gray-200 text-gray-700 hover:bg-gray-50 hover:border-gray-300 hover:shadow-sm'
        }`}
      >
        <span className="text-[11px] font-bold tracking-wider uppercase">
          {activeBranchName}
        </span>
      </button>

      {isOpen && (
          <>
            <div 
              className="fixed inset-0 z-40" 
              onClick={() => setIsOpen(false)}
            />
            <div className="absolute right-0 z-50 mt-2 w-56 overflow-hidden rounded-xl border border-gray-200 bg-white p-1.5 shadow-lg"
            >
              <div className="px-3 py-2">
                <p className="text-[10px] font-black tracking-wider text-gray-400 uppercase">
                  Global Context
                </p>
              </div>
              
              <button
                onClick={() => {
                  setActiveBranchId('ALL');
                  setIsOpen(false);
                }}
                className={`flex w-full items-center justify-between rounded-xl px-3 py-2.5 text-left text-xs font-bold transition-colors ${
                  activeBranchId === 'ALL'
                    ? 'bg-blue-50 text-blue-700'
                    : 'text-gray-700 hover:bg-gray-100/80'
                }`}
              >
                All Branches
              </button>

              <div className="my-1 border-t border-gray-100" />
              
              <div className="px-3 py-2">
                <p className="text-[10px] font-black tracking-wider text-gray-400 uppercase">
                  Local Branches
                </p>
              </div>

              {branches.map((branch) => (
                <button
                  key={branch.id}
                  onClick={() => {
                    setActiveBranchId(branch.id);
                    setIsOpen(false);
                  }}
                  className={`flex w-full items-center justify-between rounded-xl px-3 py-2.5 text-left text-xs font-bold transition-colors ${
                    activeBranchId === branch.id
                      ? 'bg-blue-50 text-blue-700'
                      : 'text-gray-700 hover:bg-gray-100/80'
                  }`}
                >
                  {branch.name}
                </button>
              ))}
            </div>
          </>
        )}
    </div>
  );
}
