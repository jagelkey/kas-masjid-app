-- Script to Cleanup Duplicate Transactions (Safe Mode)
-- How to use:
-- 1. Run the SELECT part first to see what will be deleted
-- 2. If it looks correct, run the DELETE part

-- Step 1: VIEW duplicate transactions based on identical fields (amount, type, category, date, description)
-- This identifies duplicates by looking for records with the exact same details but different IDs
SELECT *
FROM public.transactions t1
WHERE EXISTS (
    SELECT 1 
    FROM public.transactions t2
    WHERE t1.id > t2.id -- Keep the oldest one (smallest ID)
    AND t1.amount = t2.amount
    AND t1.type = t2.type
    AND t1.category = t2.category
    AND t1.transaction_date = t2.transaction_date
    AND COALESCE(t1.description, '') = COALESCE(t2.description, '')
);

-- Step 2: DELETE the duplicates identified above
-- WARNING: This action is permanent. Ensure you have backed up your data or reviewed the SELECT results first.
/*
DELETE FROM public.transactions
WHERE id IN (
    SELECT t1.id
    FROM public.transactions t1
    JOIN public.transactions t2 ON 
        t1.amount = t2.amount AND 
        t1.type = t2.type AND 
        t1.category = t2.category AND 
        t1.transaction_date = t2.transaction_date AND 
        COALESCE(t1.description, '') = COALESCE(t2.description, '')
    WHERE t1.id > t2.id -- Keep the one with the smaller ID/UUID
);
*/

-- Step 3: Verify the cleaning
-- This should return 0 rows if successful
/*
SELECT amount, type, category, transaction_date, description, COUNT(*)
FROM public.transactions
GROUP BY amount, type, category, transaction_date, description
HAVING COUNT(*) > 1;
*/
